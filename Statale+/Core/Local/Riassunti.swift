import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Riassunti delle trascrizioni con il modello on-device di Apple Intelligence (FoundationModels, iOS 26+).
/// `SystemLanguageModel.default` è sempre la versione più recente del modello, aggiornata con iOS (26.0–26.3, 26.4,
/// 27.0); il modello più grande su Private Cloud Compute richiede un entitlement che Apple concede su richiesta.
/// Il contesto è di ~4K token, quindi la lezione viene divisa in parti: per ognuna il modello produce (output guidato,
/// `@Generable`) titolo, riassunto dettagliato, punti chiave e domande; il documento finale lo compone il codice.
/// Così la lunghezza cresce con la lezione: una lezione di due ore dà una ventina di sezioni, non cinque righe.
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
    private static let istruzioni = """
        Sei un assistente che prepara appunti di studio dettagliati per uno studente universitario. Scrivi sempre in \
        italiano, in modo chiaro e completo, come appunti da cui si possa studiare senza riascoltare la lezione. \
        Usa esclusivamente le informazioni presenti nel testo che ricevi: non aggiungere argomenti, definizioni, \
        esempi o domande che non derivano dal testo. La trascrizione automatica può contenere errori di \
        riconoscimento: correggili solo quando il significato è evidente.
        """

    /// Riassume una trascrizione. `progresso` riceve (0…1, messaggio di stato).
    @concurrent
    static func riassumi(_ trascrizione: String,
                         progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard LimitiElaborazione.contenutoSufficiente(trascrizione) else { throw Errore.testoInsufficiente }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), stato == .disponibile else { throw Errore.nonDisponibile }
        progresso(0, "Verifica del contenuto…")
        guard try await eLezione(trascrizione) else { throw Errore.testoInsufficiente }
        var dimensione = 4_000
        while true {
            do {
                return try await riassumi(trascrizione, dimensione: dimensione, progresso: progresso)
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize where dimensione > 1_200 {
                dimensione = dimensione * 2 / 3   // parti più piccole e si riprova
            } catch LanguageModelSession.GenerationError.guardrailViolation {
                throw Errore.contenutoNonAmmesso
            }
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
        @Guide(description: "Titolo breve dell'argomento di questa parte, al massimo 8 parole")
        let titolo: String
        @Guide(description: "Riassunto dettagliato di questa parte in 2 o 3 paragrafi: concetti, definizioni, esempi, passaggi e collegamenti spiegati dal docente")
        let riassunto: String
        @Guide(description: "I concetti più importanti di questa parte, ognuno in una frase completa", .minimumCount(3), .maximumCount(6))
        let puntiChiave: [String]
        @Guide(description: "Domande di verifica a cui si risponde con il contenuto di questa parte", .minimumCount(2), .maximumCount(3))
        let domande: [String]
    }

    /// Controllo preliminare su un campione del testo: contiene la spiegazione di argomenti di una lezione?
    @available(iOS 26.0, *)
    private static func eLezione(_ testo: String) async throws -> Bool {
        let campione = String(testo.prefix(3_000))
        let sessione = LanguageModelSession(instructions: "Rispondi soltanto con SI oppure NO, senza altre parole.")
        let r = try await sessione.respond(to: """
            Il testo seguente è la trascrizione di una registrazione. Contiene la spiegazione di argomenti di una \
            lezione universitaria (concetti, teorie, esempi, metodi)? Rispondi NO se contiene solo saluti, prove del \
            microfono, attese, rumore, frasi ripetute o discorsi senza argomento.

            Testo:
            \(campione)
            """)
        let risposta = r.content.uppercased().folding(options: .diacriticInsensitive, locale: nil)
        return !risposta.contains("NO") || risposta.contains("SI")
    }

    @available(iOS 26.0, *)
    private static func riassumi(_ testo: String, dimensione: Int,
                                 progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        let blocchi = dividi(testo, dimensione: dimensione)
        var parti: [ParteLezione] = []
        for (i, blocco) in blocchi.enumerated() {
            try Task.checkCancellation()
            progresso(0.05 + Double(i) / Double(blocchi.count) * 0.85, "Parte \(i + 1) di \(blocchi.count)…")
            let sessione = LanguageModelSession(instructions: istruzioni)
            let r = try await sessione.respond(to: """
                Questa è la parte \(i + 1) di \(blocchi.count) della trascrizione di una lezione. Prepara gli appunti di \
                questa parte.

                Testo:
                \(blocco)
                """, generating: ParteLezione.self)
            let parte = r.content
            if !parte.senzaContenuto, parte.riassunto.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
                parti.append(parte)
            }
        }
        guard !parti.isEmpty else { throw Errore.testoInsufficiente }
        try Task.checkCancellation()
        progresso(0.92, "Sintesi finale…")
        let inBreve = try? await sintesi(parti)
        progresso(1, "Completato")
        return documento(parti, inBreve: inBreve)
    }

    /// "In breve": 4-6 frasi su tutta la lezione, dai titoli e dall'inizio dei riassunti delle parti.
    @available(iOS 26.0, *)
    private static func sintesi(_ parti: [ParteLezione]) async throws -> String? {
        var traccia = ""
        for (i, p) in parti.enumerated() {
            let riga = "\(i + 1). \(p.titolo): \(p.riassunto.prefix(260))\n"
            if traccia.count + riga.count > 7_000 { break }
            traccia += riga
        }
        let sessione = LanguageModelSession(instructions: istruzioni)
        let r = try await sessione.respond(to: """
            Questi sono gli argomenti di una lezione, nell'ordine in cui sono stati trattati. Scrivi un paragrafo di \
            4-6 frasi che descriva di cosa parla la lezione nel suo insieme e come gli argomenti si collegano. Solo il \
            paragrafo, senza titolo.

            \(traccia)
            """)
        let t = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 40 ? t : nil
    }

    @available(iOS 26.0, *)
    private static func documento(_ parti: [ParteLezione], inBreve: String?) -> String {
        var md: [String] = []
        if let inBreve { md += ["## In breve", inBreve, ""] }
        md.append("## Riassunto")
        for p in parti {
            md += ["### \(p.titolo.trimmingCharacters(in: .whitespacesAndNewlines))", p.riassunto.trimmingCharacters(in: .whitespacesAndNewlines), ""]
        }
        var visti = Set<String>()
        let punti = parti.flatMap(\.puntiChiave).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && visti.insert($0.lowercased()).inserted }
        md.append("## Punti chiave")
        md += punti.map { "- \($0)" }
        md.append("")
        let domande = parti.flatMap(\.domande).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        md.append("## Da ripassare")
        md += domande.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return md.joined(separator: "\n")
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
