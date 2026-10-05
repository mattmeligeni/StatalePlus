import Foundation
import Observation

/// Un modello locale scaricabile (Parakeet per la trascrizione, Qwen per i riassunti).
nonisolated struct ModelloLocale: Sendable {
    let nome: String
    let dimensioneMB: Int
    let installato: @Sendable () -> Bool
    /// Controllo rapido di completezza (file e dimensioni), fatto all'avvio.
    let integro: @Sendable () -> Bool
    let spazioOccupato: @Sendable () -> Int64
    /// `progresso(p, fase)`: la fase è il testo breve per l'attività di sistema ("312 di 632 MB").
    let scarica: @Sendable (_ progresso: @escaping @Sendable (Double, String) -> Void) async throws -> Void
    let elimina: @Sendable () -> Void

    static let parakeet = ModelloLocale(
        nome: "Parakeet", dimensioneMB: ParakeetLocale.dimensioneMB,
        installato: { ParakeetLocale.installato }, integro: { ParakeetLocale.integro },
        spazioOccupato: { ParakeetLocale.spazioOccupato },
        scarica: { try await ParakeetLocale.scarica(progresso: $0) }, elimina: { ParakeetLocale.elimina() })

    static let qwen = ModelloLocale(
        nome: "Qwen", dimensioneMB: QwenLocale.dimensioneMB,
        installato: { QwenLocale.installato }, integro: { QwenLocale.integro },
        spazioOccupato: { QwenLocale.spazioOccupato },
        scarica: { try await QwenLocale.scarica(progresso: $0) }, elimina: { QwenLocale.elimina() })
}

/// Stato di un modello per le impostazioni: assente, in download (con avanzamento), installato.
/// - All'avvio un modello segnato come scaricato ma incompleto si elimina, con un avviso.
/// - Un download fermato da iOS (non dall'utente) mostra un errore: prima sembrava semplicemente non partito.
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
    @ObservationIgnored private var annullatoDallUtente = false
    @ObservationIgnored private let dopoDownload: () -> Void
    @ObservationIgnored private let dopoEliminazione: () -> Void

    init(_ modello: ModelloLocale, dopoDownload: @escaping () -> Void, dopoEliminazione: @escaping () -> Void) {
        self.modello = modello
        self.dopoDownload = dopoDownload
        self.dopoEliminazione = dopoEliminazione
        if modello.installato() && !modello.integro() {
            modello.elimina()
            stato = .assente
            errore = "Il download di \(modello.nome) era incompleto ed è stato eliminato: scaricalo di nuovo."
            dopoEliminazione()
        } else {
            stato = modello.installato() ? .installato : .assente
        }
    }

    var spazioOccupato: Int64 { modello.spazioOccupato() }

    /// Lo stato si aggiorna anche se il modello si rivela rovinato durante l'uso (es. alla prima trascrizione).
    func ricontrolla() {
        guard compito == nil else { return }
        stato = modello.installato() ? .installato : .assente
    }

    /// Scarica il modello e, finito, lo imposta come motore scelto.
    func scarica() {
        guard compito == nil, stato != .installato else { return }
        errore = nil
        annullatoDallUtente = false
        stato = .download(0)
        let modello = modello
        compito = Task {
            do {
                try await EsecuzioneEstesa.esegui(titolo: "Download di \(modello.nome)", sottotitolo: "\(modello.dimensioneMB) MB") { sistema in
                    try await modello.scarica { p, fase in
                        sistema(p, fase: fase)
                        Task { @MainActor in if case .download = self.stato { self.stato = .download(p) } }
                    }
                }
                stato = .installato
                dopoDownload()
            } catch {
                stato = modello.installato() ? .installato : .assente
                if !annullatoDallUtente {
                    errore = error is CancellationError
                        ? "Download interrotto da iOS. Riprova tenendo l'app aperta fino alla fine."
                        : (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            compito = nil
        }
    }

    func annulla() {
        annullatoDallUtente = true
        compito?.cancel()
    }

    func elimina() {
        annullatoDallUtente = true
        compito?.cancel()
        modello.elimina()
        stato = .assente
        errore = nil
        dopoEliminazione()
    }
}
