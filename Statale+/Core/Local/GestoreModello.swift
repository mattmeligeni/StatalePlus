import Foundation
import Observation

/// Un modello locale scaricabile (Parakeet per la trascrizione, Qwen per i riassunti).
nonisolated struct ModelloLocale: Sendable {
    let nome: String
    let nomeCompleto: String
    let dimensioneMB: Int
    let installato: @Sendable () -> Bool
    let spazioOccupato: @Sendable () -> Int64
    let scarica: @Sendable (_ progresso: @escaping @Sendable (Double) -> Void) async throws -> Void
    let elimina: @Sendable () -> Void

    static let parakeet = ModelloLocale(
        nome: "Parakeet", nomeCompleto: "Parakeet TDT 0.6B v3 Ultra", dimensioneMB: ParakeetLocale.dimensioneMB,
        installato: { ParakeetLocale.installato }, spazioOccupato: { ParakeetLocale.spazioOccupato },
        scarica: { try await ParakeetLocale.scarica(progresso: $0) }, elimina: { ParakeetLocale.elimina() })

    static let qwen = ModelloLocale(
        nome: "Qwen", nomeCompleto: "Qwen 3.5 4B", dimensioneMB: QwenLocale.dimensioneMB,
        installato: { QwenLocale.installato }, spazioOccupato: { QwenLocale.spazioOccupato },
        scarica: { try await QwenLocale.scarica(progresso: $0) }, elimina: { QwenLocale.elimina() })
}

/// Stato di un modello per le impostazioni: assente, in download (con avanzamento), installato.
@Observable
final class GestoreModello {
    enum Stato: Equatable {
        case assente
        case download(Double)
        case installato
    }

    let modello: ModelloLocale
    private(set) var stato: Stato
    private(set) var errore: String?
    @ObservationIgnored private var compito: Task<Void, Never>?
    @ObservationIgnored private let dopoDownload: () -> Void
    @ObservationIgnored private let dopoEliminazione: () -> Void

    init(_ modello: ModelloLocale, dopoDownload: @escaping () -> Void, dopoEliminazione: @escaping () -> Void) {
        self.modello = modello
        self.stato = modello.installato() ? .installato : .assente
        self.dopoDownload = dopoDownload
        self.dopoEliminazione = dopoEliminazione
    }

    var spazioOccupato: Int64 { modello.spazioOccupato() }

    /// Scarica il modello e, finito, lo imposta come motore scelto.
    func scarica() {
        guard compito == nil, stato != .installato else { return }
        errore = nil
        stato = .download(0)
        let modello = modello
        compito = Task {
            do {
                try await EsecuzioneEstesa.esegui(titolo: "Download di \(modello.nome)", sottotitolo: modello.nomeCompleto, tipo: "download") { sistema in
                    try await modello.scarica { p in
                        sistema(p, fase: "\(Int(p * Double(modello.dimensioneMB))) di \(modello.dimensioneMB) MB")
                        Task { @MainActor in if case .download = self.stato { self.stato = .download(p) } }
                    }
                }
                stato = .installato
                dopoDownload()
            } catch is CancellationError {
                stato = modello.installato() ? .installato : .assente
            } catch {
                errore = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                stato = modello.installato() ? .installato : .assente
            }
            compito = nil
        }
    }

    func annulla() {
        compito?.cancel()
    }

    func elimina() {
        compito?.cancel()
        modello.elimina()
        stato = .assente
        dopoEliminazione()
    }
}
