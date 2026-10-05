import Foundation
import Observation

/// Stato del modello Whisper per le Impostazioni: assente, in download (con avanzamento), installato.
@Observable
final class GestoreWhisper {
    enum Stato: Equatable {
        case assente
        case download(Double)
        case installato
    }

    private(set) var stato: Stato = WhisperLocale.installato ? .installato : .assente
    private(set) var errore: String?
    @ObservationIgnored private var compito: Task<Void, Never>?

    /// Scarica il modello e, finito, imposta Whisper come motore di trascrizione.
    func scarica() {
        guard compito == nil, stato != .installato else { return }
        errore = nil
        stato = .download(0)
        compito = Task {
            do {
                try await EsecuzioneEstesa.esegui(titolo: "Download di Whisper",
                                                  sottotitolo: "Whisper Large v3 Turbo") { sistema in
                    try await WhisperLocale.scarica { p in
                        sistema(p, fase: "\(Int(p * Double(WhisperLocale.dimensioneMB))) di \(WhisperLocale.dimensioneMB) MB")
                        Task { @MainActor in if case .download = self.stato { self.stato = .download(p) } }
                    }
                }
                stato = .installato
                Preferenze.motoreTrascrizione = .whisper
            } catch is CancellationError {
                WhisperLocale.elimina()
                stato = .assente
            } catch {
                WhisperLocale.elimina()
                errore = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                stato = .assente
            }
            compito = nil
        }
    }

    func annulla() {
        compito?.cancel()
    }

    /// Elimina il modello e torna ad Apple.
    func elimina() {
        compito?.cancel()
        WhisperLocale.elimina()
        stato = .assente
        if Preferenze.motoreTrascrizione == .whisper { Preferenze.motoreTrascrizione = .apple }
    }
}
