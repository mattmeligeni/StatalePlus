import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Motori dei riassunti e del glossario del corso, in Altro › IA. La trascrizione resta sempre sul telefono.
nonisolated enum MotoreRiassunto: String, CaseIterable, Sendable {
    /// Modello di Apple Intelligence sul telefono (FoundationModels): offline, contesto di 4K token (8K da iOS 27).
    case apple
    /// Apple Intelligence su Private Cloud Compute (online, iOS 27): solo con l'entitlement concesso da Apple.
    case cloud

    var nome: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .cloud: "Apple Intelligence online"
        }
    }
}

/// Riassunti delle trascrizioni con il modello on-device di Apple Intelligence (FoundationModels, iOS 26+).
/// `SystemLanguageModel.default` è sempre la versione più recente del modello, aggiornata con iOS.
///
/// Il contesto è piccolo (4096 token fino a iOS 26, 8192 da iOS 27), quindi la lezione si divide in parti: per
/// ognuna il modello produce (output guidato, `@Generable`) titolo, riassunto dettagliato, punti chiave e domande;
/// il documento finale lo compone il codice. Così la lunghezza cresce con la lezione.
/// Per sfruttare al massimo il modello:
/// - le parti sono grandi quanto il contesto permette, misurato in token (`contextSize`, `tokenCount`, iOS 26.4+):
///   meno parti significa argomenti meno spezzati e meno tempo; se una parte non entra si divide solo quella;
/// - ogni parte riceve i titoli già scritti, per non ripetere gli argomenti e continuare quelli lasciati a metà, e i
///   termini del glossario del corso che vi compaiono (anche storpiati), per correggere gli errori di trascrizione;
/// - temperatura bassa: appunti fedeli al testo, non frasi creative;
/// - una passata finale guidata sceglie "In breve", 10-15 punti chiave e 8-12 domande dagli appunti di tutte le parti
///   (prima si elencavano tutti: in una lezione di due ore erano più di cento);
/// - il modello gira in un processo di sistema e continua anche con l'app in background, dove iOS può limitarne le
///   richieste: si riprova dopo una pausa invece di fallire.
nonisolated enum AppleIntelligence {
    enum Stato: Equatable {
        case disponibile
        case nonAttiva          // dispositivo compatibile, Apple Intelligence disattivata
        case inPreparazione     // modello in download
        case nonSupportata      // iOS < 26, dispositivo non compatibile o lingua non supportata
    }

    static var stato: Stato {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .nonSupportata }
        let modello = SystemLanguageModel.default
        switch modello.availability {
        case .available:
            return modello.supportsLocale(Formats.it) ? .disponibile : .nonSupportata
        case .unavailable(.appleIntelligenceNotEnabled): return .nonAttiva
        case .unavailable(.modelNotReady): return .inPreparazione
        default: return .nonSupportata
        }
        #else
        return .nonSupportata
        #endif
    }

    enum Errore: LocalizedError {
        case nonDisponibile, contenutoNonAmmesso, testoInsufficiente
        var errorDescription: String? {
            switch self {
            case .nonDisponibile: "Apple Intelligence non è disponibile su questo dispositivo."
            case .contenutoNonAmmesso: "Il modello non ha potuto elaborare parte del contenuto."
            case .testoInsufficiente: "La trascrizione non contiene abbastanza contenuto di lezione per un riassunto."
            }
        }
    }

    /// Il nome della materia NON entra mai nei prompt: con una trascrizione povera il modello lo userebbe
    /// per inventare una lezione plausibile. Si lavora solo sul testo trascritto.
    static let istruzioni = """
        Sei un assistente che prepara appunti di studio dettagliati per uno studente universitario. Scrivi sempre in \
        italiano, in modo chiaro e completo, come appunti da cui si possa studiare senza riascoltare la lezione. \
        Usa esclusivamente le informazioni presenti nel testo che ricevi: non aggiungere argomenti, definizioni, \
        esempi o domande che non derivano dal testo. La trascrizione automatica può contenere errori di \
        riconoscimento: correggili solo quando il significato è evidente. Tralascia saluti, avvisi organizzativi e \
        pause, salvo indicazioni utili per l'esame.
        """

    /// Riassume una trascrizione. `progresso` riceve (0…1, messaggio di stato).
    @concurrent
    /// `glossario`: termini del corso; per ogni parte si passano al modello quelli che vi compaiono, anche storpiati.
    static func riassumi(_ trascrizione: String, glossario: [String] = [],
                         progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard LimitiElaborazione.contenutoSufficiente(trascrizione) else { throw Errore.testoInsufficiente }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), stato == .disponibile else { throw Errore.nonDisponibile }
        progresso(0, "Verifica del contenuto")
        guard try await eLezione(trascrizione) else { throw Errore.testoInsufficiente }
        do {
            return try await riassumiAParti(trascrizione, glossario: glossario, progresso: progresso)
        } catch where violaProtezioni(error) {
            throw Errore.contenutoNonAmmesso
        }
        #else
        throw Errore.nonDisponibile
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct ParteLezione {
        @Guide(description: "true solo se il testo non spiega alcun argomento (saluti, attese, rumore, frasi senza contenuto)")
        let senzaContenuto: Bool
        @Guide(description: "Titolo breve dell'argomento di questa parte, al massimo 8 parole. Se continua un argomento già trattato, usa lo stesso titolo")
        let titolo: String
        @Guide(description: "Riassunto dettagliato di questa parte in 2 o 3 paragrafi: concetti, definizioni, esempi, passaggi e collegamenti spiegati dal docente")
        let riassunto: String
        @Guide(description: "I concetti più importanti di questa parte, ognuno in una frase completa", .minimumCount(2), .maximumCount(5))
        let puntiChiave: [String]
        @Guide(description: "Domande di verifica a cui si risponde con il contenuto di questa parte", .minimumCount(1), .maximumCount(3))
        let domande: [String]
    }

    @available(iOS 26.0, *)
    @Generable
    struct SintesiLezione {
        @Guide(description: "Un paragrafo di 4-6 frasi su cosa tratta la lezione nel suo insieme e come si collegano gli argomenti")
        let inBreve: String
        @Guide(description: "I concetti più importanti di tutta la lezione, ognuno in una frase completa, senza ripetizioni", .minimumCount(6), .maximumCount(15))
        let puntiChiave: [String]
        @Guide(description: "Domande di verifica sugli argomenti principali della lezione, senza ripetizioni", .minimumCount(5), .maximumCount(12))
        let domande: [String]
    }

    /// Controllo preliminare su un campione del testo: contiene la spiegazione di argomenti di una lezione?
    @available(iOS 26.0, *)
    private static func eLezione(_ testo: String) async throws -> Bool {
        let campione = String(testo.prefix(3_000))
        let sessione = LanguageModelSession(instructions: "Rispondi soltanto con SI oppure NO, senza altre parole.")
        let r = try await conRiprova {
            try await sessione.respond(to: """
                Il testo seguente è la trascrizione di una registrazione. Contiene la spiegazione di argomenti di una \
                lezione universitaria (concetti, teorie, esempi, metodi)? Rispondi NO se contiene solo saluti, prove \
                del microfono, attese, rumore, frasi ripetute o discorsi senza argomento.

                Testo:
                \(campione)
                """, options: GenerationOptions(temperature: 0))
        }
        let risposta = r.content.uppercased().folding(options: .diacriticInsensitive, locale: nil)
        return !risposta.contains("NO") || risposta.contains("SI")
    }

    /// Caratteri di trascrizione per parte: il contesto meno istruzioni, schema, titoli già scritti e risposta,
    /// convertito in caratteri con il rapporto caratteri/token misurato sul testo stesso (l'italiano trascritto, con
    /// gli errori, occupa più token del previsto). Senza le API di conteggio (prima di iOS 26.4): 4000 caratteri.
    @available(iOS 26.0, *)
    private static func caratteriPerParte(_ testo: String) async -> Int {
        guard #available(iOS 26.4, *) else { return 4_000 }
        let modello = SystemLanguageModel.default
        do {
            let fissi = try await modello.tokenCount(for: Instructions(istruzioni))
                + modello.tokenCount(for: ParteLezione.generationSchema)
            let campione = String(testo.prefix(6_000))
            let tokenCampione = max(try await modello.tokenCount(for: Prompt(campione)), 1)
            let caratteriPerToken = Double(campione.count) / Double(tokenCampione)
            // Risposta (~900 token), richiesta con i titoli già scritti e i termini del glossario (~550) e un
            // margine del 10%.
            let disponibili = modello.contextSize - fissi - 900 - 550
            return max(2_000, Int(Double(disponibili) * caratteriPerToken * 0.9))
        } catch {
            return 4_000
        }
    }

    @available(iOS 26.0, *)
    private static func riassumiAParti(_ testo: String, glossario: [String],
                                       progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        var blocchi = dividi(testo, dimensione: await caratteriPerParte(testo))
        var parti: [ParteLezione] = []
        var i = 0
        let opzioni = GenerationOptions(temperature: 0.3)
        while i < blocchi.count {
            try Task.checkCancellation()
            let blocco = blocchi[i]
            progresso(0.05 + Double(i) / Double(blocchi.count) * 0.85, "Parte \(i + 1) di \(blocchi.count)")
            // Gli ultimi titoli (al massimo 12): bastano per la continuità e restano piccoli nel contesto.
            let titoli = parti.suffix(12).map { "- \($0.titolo)" }.joined(separator: "\n")
            var richiesta = "Questa è la parte \(i + 1) di \(blocchi.count) della trascrizione di una lezione. Prepara gli appunti di questa parte.\n"
            if !titoli.isEmpty {
                richiesta += "Argomenti delle parti precedenti (non ripetere ciò che è già stato spiegato; se la parte continua uno di questi argomenti, usa lo stesso titolo):\n\(titoli)\n"
            }
            richiesta += GlossarioCorso.rigaPrompt(GlossarioCorso.pertinenti(glossario, a: blocco, massimo: 25))
            richiesta += "\nTesto:\n\(blocco)"
            let sessione = LanguageModelSession(instructions: istruzioni)
            let r: LanguageModelSession.Response<ParteLezione>
            do {
                r = try await conRiprova { try await sessione.respond(to: richiesta, generating: ParteLezione.self, options: opzioni) }
            } catch where superaContesto(error) && blocco.count > 1_200 {
                // Solo questa parte si divide: le altre restano come sono (prima si ricominciava da capo).
                blocchi.replaceSubrange(i...i, with: dividi(blocco, dimensione: blocco.count * 2 / 3))
                continue
            }
            i += 1
            let parte = r.content
            if !parte.senzaContenuto, parte.riassunto.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
                parti.append(parte)
            }
        }
        guard !parti.isEmpty else { throw Errore.testoInsufficiente }
        try Task.checkCancellation()
        progresso(0.92, "Sintesi finale")
        let sintesi = try? await sintesi(parti)
        progresso(1, "Completato")
        return documento(parti, sintesi: sintesi)
    }

    /// "In breve", punti chiave e domande di tutta la lezione, dai titoli e dai punti chiave delle parti (tagliati
    /// per stare nel contesto).
    @available(iOS 26.0, *)
    private static func sintesi(_ parti: [ParteLezione]) async throws -> SintesiLezione {
        let limite = SystemLanguageModel.default.contextSize >= 8_000 ? 14_000 : 6_000
        var traccia = ""
        for (i, p) in parti.enumerated() {
            let punti = p.puntiChiave.prefix(3).map { "  · \($0)" }.joined(separator: "\n")
            let blocco = "\(i + 1). \(p.titolo)\n\(punti)\n"
            if traccia.count + blocco.count > limite { break }
            traccia += blocco
        }
        let sessione = LanguageModelSession(instructions: istruzioni)
        return try await conRiprova {
            try await sessione.respond(to: """
                Questi sono gli argomenti di una lezione, nell'ordine in cui sono stati trattati, con i concetti \
                principali di ognuno. Prepara la sintesi di tutta la lezione.

                \(traccia)
                """, generating: SintesiLezione.self, options: GenerationOptions(temperature: 0.3)).content
        }
    }

    /// Il documento: parti consecutive con lo stesso titolo (un argomento spezzato fra due parti) si uniscono.
    @available(iOS 26.0, *)
    private static func documento(_ parti: [ParteLezione], sintesi: SintesiLezione?) -> String {
        var sezioni: [(titolo: String, testo: [String])] = []
        for p in parti {
            let titolo = p.titolo.trimmingCharacters(in: .whitespacesAndNewlines)
            let testo = p.riassunto.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ultimo = sezioni.last, ultimo.titolo.compare(titolo, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                sezioni[sezioni.count - 1].testo.append(testo)
            } else {
                sezioni.append((titolo, [testo]))
            }
        }
        func pulisci(_ elenco: [String], massimo: Int) -> [String] {
            var visti = Set<String>()
            return elenco.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && visti.insert($0.lowercased()).inserted }
                .prefix(massimo).map { $0 }
        }
        let inBreve = sintesi?.inBreve.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let punti = pulisci(sintesi?.puntiChiave ?? parti.flatMap { $0.puntiChiave.prefix(2) }, massimo: 15)
        let domande = pulisci(sintesi?.domande ?? parti.flatMap { $0.domande.prefix(1) }, massimo: 12)

        var md: [String] = []
        if inBreve.count > 40 { md += ["## In breve", inBreve, ""] }
        md.append("## Riassunto")
        for s in sezioni { md += ["### \(s.titolo)", s.testo.joined(separator: "\n\n"), ""] }
        md.append("## Punti chiave")
        md += punti.map { "- \($0)" }
        md.append("")
        md.append("## Da ripassare")
        md += domande.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return md.joined(separator: "\n")
    }

    /// Il testo è stato fermato dalle protezioni del modello (errore di iOS 26 o di iOS 27: da iOS 27 il framework
    /// lancia `LanguageModelError` al posto di `GenerationError`).
    @available(iOS 26.0, *)
    static func violaProtezioni(_ error: Error) -> Bool {
        if case LanguageModelSession.GenerationError.guardrailViolation = error { return true }
        if #available(iOS 27.0, *), case LanguageModelError.guardrailViolation = error { return true }
        return false
    }

    /// La richiesta non entra nel contesto del modello (errore di iOS 26 o di iOS 27).
    @available(iOS 26.0, *)
    static func superaContesto(_ error: Error) -> Bool {
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error { return true }
        if #available(iOS 27.0, *), case LanguageModelError.contextSizeExceeded = error { return true }
        return false
    }

    /// Esegue una richiesta e, se iOS limita il modello (app in background, sistema occupato), riprova dopo una pausa
    /// (fino alla data indicata da iOS, al massimo un minuto; 6 tentativi).
    @available(iOS 26.0, *)
    static func conRiprova<T>(_ richiesta: () async throws -> T) async throws -> T {
        var attesa: Double = 5
        for _ in 0..<6 {
            do {
                return try await richiesta()
            } catch {
                guard let pausa = pausaPerLimite(error, predefinita: attesa) else { throw error }
                try await Task.sleep(for: .seconds(pausa))
                attesa = min(attesa * 2, 60)
            }
        }
        return try await richiesta()
    }

    /// Secondi da attendere se l'errore è un limite temporaneo; nil per gli altri errori.
    @available(iOS 26.0, *)
    private static func pausaPerLimite(_ error: Error, predefinita: Double) -> Double? {
        if #available(iOS 27.0, *), case LanguageModelError.rateLimited(let info) = error {
            return min(max(info.resetDate?.timeIntervalSinceNow ?? predefinita, 1), 60)
        }
        if #available(iOS 27.0, *), case LanguageModelError.timeout = error { return predefinita }
        switch error {
        case LanguageModelSession.GenerationError.rateLimited, LanguageModelSession.GenerationError.concurrentRequests:
            return predefinita
        default:
            return nil
        }
    }
    #endif

    /// Divide il testo in parti di circa `dimensione` caratteri, rispettando i paragrafi quando possibile.
    static func dividi(_ testo: String, dimensione: Int) -> [String] {
        var parti: [String] = []
        var corrente = ""
        for paragrafo in testo.components(separatedBy: "\n") where !paragrafo.trimmingCharacters(in: .whitespaces).isEmpty {
            if corrente.count + paragrafo.count > dimensione, !corrente.isEmpty {
                parti.append(corrente)
                corrente = ""
            }
            if paragrafo.count > dimensione {
                var resto = Substring(paragrafo)
                while resto.count > dimensione {
                    let taglio = resto.index(resto.startIndex, offsetBy: dimensione)
                    let spazio = resto[..<taglio].lastIndex(of: " ") ?? taglio
                    parti.append(String(resto[..<spazio]))
                    resto = resto[spazio...].dropFirst()
                }
                corrente = String(resto)
            } else {
                corrente += (corrente.isEmpty ? "" : "\n") + paragrafo
            }
        }
        if !corrente.isEmpty { parti.append(corrente) }
        return parti
    }
}

/// Soglie minime per trascrizione e riassunto: evitano elaborazioni inutili e riassunti inventati su audio vuoti.
nonisolated enum LimitiElaborazione {
    static let minDurataTrascrizione: TimeInterval = 60        // 1 minuto
    static let minDurataRiassunto: TimeInterval = 5 * 60       // 5 minuti
    static let minParoleRiassunto = 150
    static let minParoleDiverseRiassunto = 60   // il parlato di riempimento ripetuto ha poco vocabolario

    static func parole(_ testo: String) -> Int { testo.split(whereSeparator: \.isWhitespace).count }

    static func paroleDiverse(_ testo: String) -> Int {
        Set(testo.lowercased().split { !$0.isLetter }.filter { $0.count > 2 }).count
    }

    static func contenutoSufficiente(_ testo: String) -> Bool {
        parole(testo) >= minParoleRiassunto && paroleDiverse(testo) >= minParoleDiverseRiassunto
    }

    /// Motivo per cui la trascrizione non è disponibile (nil = disponibile).
    static func bloccoTrascrizione(_ r: Registrazione) -> String? {
        r.durata < minDurataTrascrizione ? "La trascrizione è disponibile per registrazioni di almeno 1 minuto." : nil
    }

    /// Motivo per cui il riassunto non è disponibile (nil = disponibile).
    static func bloccoRiassunto(_ r: Registrazione, trascrizione: String?) -> String? {
        if r.durata < minDurataRiassunto { return "Il riassunto è disponibile per registrazioni di almeno 5 minuti." }
        guard let trascrizione else { return "Trascrivi prima la registrazione per poterla riassumere." }
        if !contenutoSufficiente(trascrizione) {
            return "La trascrizione non contiene abbastanza parlato per un riassunto."
        }
        return nil
    }
}
