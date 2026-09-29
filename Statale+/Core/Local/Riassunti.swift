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
        case nonDisponibile, contenutoNonAmmesso
        var errorDescription: String? {
            switch self {
            case .nonDisponibile: "Apple Intelligence non è disponibile su questo dispositivo."
            case .contenutoNonAmmesso: "Il modello non ha potuto elaborare parte del contenuto."
            }
        }
    }

    private static let istruzioni = """
        Sei un assistente che prende appunti per uno studente universitario. Scrivi sempre in italiano, \
        in modo chiaro e fedele al contenuto della lezione, senza inventare informazioni.
        """

    /// Riassume una trascrizione. `progresso` riceve (0…1, messaggio di stato).
    @concurrent
    static func riassumi(_ trascrizione: String, titolo: String,
                         progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), stato == .disponibile else { throw Errore.nonDisponibile }
        var dimensione = 5_000
        while true {
            do {
                return try await riassumi(trascrizione, titolo: titolo, dimensione: dimensione, progresso: progresso)
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
    @available(iOS 26.0, *)
    private static func riassumi(_ testo: String, titolo: String, dimensione: Int,
                                 progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        // 1. Ogni parte → appunti. 2. Appunti troppo lunghi → di nuovo condensati. 3. Riassunto finale.
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
                    Questa è una parte della trascrizione di una lezione. Estrai i contenuti principali in 3-8 punti \
                    elenco concisi, senza introduzione e senza commenti.

                    \(parte)
                    """)
                ridotti.append(r.content)
            }
            appunti = ridotti.joined(separator: "\n")
            giro += 1
        }
        try Task.checkCancellation()
        progresso(0.9, "Scrittura del riassunto…")
        let sessione = LanguageModelSession(instructions: istruzioni)
        let finale = try await sessione.respond(to: """
            Questi sono gli appunti della lezione "\(titolo)". Scrivi in Markdown:
            ## Riassunto
            uno o due paragrafi che spiegano gli argomenti trattati.
            ## Punti chiave
            un elenco puntato dei concetti più importanti.
            ## Da ripassare
            da 3 a 5 domande di verifica sugli argomenti della lezione.

            Appunti:
            \(appunti)
            """)
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
