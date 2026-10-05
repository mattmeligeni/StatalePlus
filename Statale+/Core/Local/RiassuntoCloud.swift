import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence su Private Cloud Compute (iOS 27): il modello più grande di Apple sui suoi server, con un
/// contesto di 32K token (8 volte quello sul telefono). Una lezione di due ore si riassume in 2-3 blocchi invece di
/// decine. Apple non conserva né vede i dati; gratuito per lo sviluppatore (App Store Small Business Program), con un
/// limite giornaliero di richieste per utente che si alza con iCloud+.
///
/// Serve l'entitlement `com.apple.developer.private-cloud-compute`, che Apple concede su richiesta: finché non è in
/// `Statale+.entitlements` la chiave `StatalePCCAutorizzata` di Info.plist resta `NO` e l'opzione non compare.
nonisolated enum NuvolaApple {
    static var autorizzata: Bool { Bundle.main.object(forInfoDictionaryKey: "StatalePCCAutorizzata") as? Bool ?? false }

    enum Stato: Equatable {
        case nonAutorizzata
        case nonDisponibile(String)
        case disponibile
    }

    static var stato: Stato {
        guard autorizzata else { return .nonAutorizzata }
        #if canImport(FoundationModels)
        guard #available(iOS 27.0, *) else { return .nonDisponibile("Richiede iOS 27.") }
        return switch PrivateCloudComputeLanguageModel().availability {
        case .available: .disponibile
        case .unavailable(.deviceNotEligible): .nonDisponibile("Questo iPhone non supporta Apple Intelligence.")
        case .unavailable(.systemNotReady): .nonDisponibile("Apple Intelligence non è ancora pronta: riprova tra poco.")
        @unknown default: .nonDisponibile("Non disponibile in questo momento.")
        }
        #else
        return .nonDisponibile("Non disponibile.")
        #endif
    }

    /// Stato del limite giornaliero: testo da mostrare (nil se lontano dal limite).
    static var notaLimite: String? {
        #if canImport(FoundationModels)
        guard autorizzata, #available(iOS 27.0, *) else { return nil }
        let q = PrivateCloudComputeLanguageModel().quotaUsage
        if q.isLimitReached {
            let quando = q.resetDate.map { " fino a \($0.italiano(date: .omitted, time: .shortened))" } ?? " per oggi"
            return "Hai usato tutte le richieste disponibili\(quando)."
        }
        if case .belowLimit(let info) = q.status, info.isApproachingLimit { return "Stai per raggiungere il limite giornaliero." }
        #endif
        return nil
    }

    /// Mostra l'offerta di Apple per avere più richieste (iCloud+), se disponibile.
    static var puòAumentareLimite: Bool {
        #if canImport(FoundationModels)
        if autorizzata, #available(iOS 27.0, *) { return PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion != nil }
        #endif
        return false
    }

    @MainActor
    static func mostraAumentoLimite() {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) { PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show() }
        #endif
    }

    enum Errore: LocalizedError {
        case nonDisponibile
        var errorDescription: String? { "Apple Intelligence online non è disponibile: controlla la connessione o usa un modello sul telefono." }
    }

    /// Riassunto a sezioni con blocchi da ~6000 parole (stanno comodi nei 32K token insieme alla risposta).
    @concurrent
    static func riassumi(_ trascrizione: String, progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 27.0, *), stato == .disponibile else { throw Errore.nonDisponibile }
        let modello = PrivateCloudComputeLanguageModel()
        progresso(0, "Invio ad Apple Intelligence")
        return try await RiassuntoASezioni.riassumi(trascrizione, paroleBlocco: 6_000, progresso: progresso) { richiesta, massimo in
            let sessione = LanguageModelSession(model: modello, instructions: RiassuntoASezioni.istruzioni)
            return try await sessione.respond(to: richiesta, options: GenerationOptions(maximumResponseTokens: massimo)).content
        }
        #else
        throw Errore.nonDisponibile
        #endif
    }

    /// Più risposte brevi (es. gli elenchi del glossario del corso).
    @concurrent
    static func rispondi(_ richieste: [String], istruzioni: String,
                         progresso: @escaping @Sendable (Double) -> Void) async throws -> [String] {
        #if canImport(FoundationModels)
        guard #available(iOS 27.0, *), stato == .disponibile else { throw Errore.nonDisponibile }
        let modello = PrivateCloudComputeLanguageModel()
        var risposte: [String] = []
        for (i, r) in richieste.enumerated() {
            try Task.checkCancellation()
            progresso(Double(i) / Double(max(richieste.count, 1)))
            let sessione = LanguageModelSession(model: modello, instructions: istruzioni)
            risposte.append(try await sessione.respond(to: r).content)
        }
        progresso(1)
        return risposte
        #else
        throw Errore.nonDisponibile
        #endif
    }
}
