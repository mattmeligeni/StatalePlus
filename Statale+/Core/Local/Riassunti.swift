import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Riassunti delle trascrizioni con il modello on-device di Apple Intelligence (FoundationModels, iOS 26+).
/// Il contesto del modello è limitato (~4K token): la trascrizione viene divisa in parti, ciascuna ridotta ad appunti,
/// poi gli appunti vengono uniti in un riassunto finale in Markdown (riassunto, punti chiave, domande di ripasso).
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
            return modello.supportsLocale(Locale(identifier: "it_IT")) ? .disponibile : .nonSupportata
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
        Sei un assistente che prende appunti per uno studente universitario. Scrivi sempre in italiano. \
        Usa esclusivamente le informazioni presenti nel testo che ricevi: non aggiungere argomenti, definizioni, \
        esempi o domande che non derivano direttamente dal testo. Se il testo non contiene contenuti di una lezione \
        (è vuoto, incomprensibile, solo saluti, rumore o frasi senza argomento), rispondi soltanto con \(segnaleVuoto).
        """

    /// Risposta attesa quando non c'è materiale da riassumere.
    static let segnaleVuoto = "CONTENUTO_INSUFFICIENTE"

    private static func vuoto(_ risposta: String) -> Bool {
        risposta.uppercased().contains(segnaleVuoto) || risposta.trimmingCharacters(in: .whitespacesAndNewlines).count < 20
    }

    /// Riassume una trascrizione. `progresso` riceve (0…1, messaggio di stato).
    @concurrent
    static func riassumi(_ trascrizione: String,
                         progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard LimitiElaborazione.contenutoSufficiente(trascrizione) else { throw Errore.testoInsufficiente }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), stato == .disponibile else { throw Errore.nonDisponibile }
        progresso(0, "Verifica del contenuto…")
        guard try await eLezione(trascrizione) else { throw Errore.testoInsufficiente }
        var dimensione = 5_000
        while true {
            do {
                return try await riassumi(trascrizione, dimensione: dimensione, progresso: progresso)
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize where dimensione > 1_500 {
                dimensione /= 2   // parti più piccole e si riprova
            } catch LanguageModelSession.GenerationError.guardrailViolation {
                throw Errore.contenutoNonAmmesso
            }
        }
        #else
        throw Errore.nonDisponibile
        #endif
    }

    #if canImport(FoundationModels)
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
        // 1. Ogni parte → appunti (le parti senza contenuto vengono scartate).
        // 2. Appunti troppo lunghi → di nuovo condensati. 3. Riassunto finale, solo dagli appunti.
        var appunti = testo
        var giro = 0
        while appunti.count > dimensione {
            let parti = dividi(appunti, dimensione: dimensione)
            var ridotti: [String] = []
            for (i, parte) in parti.enumerated() {
                try Task.checkCancellation()
                progresso(Double(i) / Double(parti.count) * 0.85, giro == 0 ? "Lettura della parte \(i + 1) di \(parti.count)…" : "Unione degli appunti…")
                let sessione = LanguageModelSession(instructions: istruzioni)
                let r = try await sessione.respond(to: """
                    Questa è una parte della trascrizione di una lezione. Estrai i contenuti presenti nel testo in 3-8 \
                    punti elenco concisi, senza introduzione e senza commenti.

                    Testo:
                    \(parte)
                    """)
                if !vuoto(r.content) { ridotti.append(r.content) }
            }
            guard !ridotti.isEmpty else { throw Errore.testoInsufficiente }
            appunti = ridotti.joined(separator: "\n")
            giro += 1
        }
        try Task.checkCancellation()
        progresso(0.9, "Scrittura del riassunto…")
        let sessione = LanguageModelSession(instructions: istruzioni)
        let finale = try await sessione.respond(to: """
            A partire SOLO dal testo seguente, scrivi in Markdown:
            ## Riassunto
            uno o due paragrafi che spiegano gli argomenti presenti nel testo.
            ## Punti chiave
            un elenco puntato dei concetti più importanti presenti nel testo.
            ## Da ripassare
            da 3 a 5 domande di verifica che si possono rispondere con il testo.
            Se il testo non basta per un riassunto, rispondi soltanto con \(segnaleVuoto).

            Testo:
            \(appunti)
            """)
        guard !vuoto(finale.content) else { throw Errore.testoInsufficiente }
        progresso(1, "Completato")
        return finale.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
