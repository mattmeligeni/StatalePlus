import Foundation
import Observation
import UIKit

/// Trascrizioni e riassunti in corso, indipendenti dalla schermata aperta (si può uscire dal dettaglio).
@Observable
final class ElaborazioniAudio {
    enum Tipo { case trascrizione, riassunto, miglioramento }

    struct Stato: Equatable {
        var progresso: Double
        var messaggio: String
    }

    private(set) var trascrizioni: [UUID: Stato] = [:]
    private(set) var riassunti: [UUID: Stato] = [:]
    private(set) var miglioramenti: [UUID: Stato] = [:]
    private(set) var errori: [UUID: String] = [:]
    private(set) var erroriMiglioramento: [UUID: String] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    func stato(_ tipo: Tipo, _ id: UUID) -> Stato? {
        switch tipo {
        case .trascrizione: trascrizioni[id]
        case .riassunto: riassunti[id]
        case .miglioramento: miglioramenti[id]
        }
    }

    /// Volume e rumore di fondo (`MiglioramentoAudio`): l'audio migliorato sostituisce quello della registrazione,
    /// l'originale resta. Non parte mentre la stessa registrazione viene trascritta (e viceversa).
    func migliora(_ r: Registrazione, in store: RecordingStore) {
        guard miglioramenti[r.id] == nil, trascrizioni[r.id] == nil else { return }
        erroriMiglioramento[r.id] = nil
        miglioramenti[r.id] = Stato(progresso: 0, messaggio: "Miglioramento dell'audio…")
        let id = r.id
        tasks["m\(id)"] = Task {
            // Qualche decina di secondi in più se si esce dall'app: basta per le registrazioni brevi.
            let bg = UIApplication.shared.beginBackgroundTask(withName: "Miglioramento audio")
            defer { if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) } }
            do {
                try await store.migliora(id) { p in
                    Task { @MainActor in self.miglioramenti[id]?.progresso = p }
                }
            } catch is CancellationError {
            } catch {
                erroriMiglioramento[id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            miglioramenti[id] = nil
            tasks["m\(id)"] = nil
        }
    }

    func trascrivi(_ r: Registrazione, in store: RecordingStore) {
        guard trascrizioni[r.id] == nil else { return }
        if miglioramenti[r.id] != nil { errori[r.id] = "Attendi la fine del miglioramento dell'audio."; return }
        if let motivo = LimitiElaborazione.bloccoTrascrizione(r) { errori[r.id] = motivo; return }
        errori[r.id] = nil
        trascrizioni[r.id] = Stato(progresso: 0, messaggio: "Preparazione…")
        let url = store.url(for: r)
        let id = r.id
        tasks["t\(id)"] = Task {
            do {
                let testo = try await Trascrittore.trascrivi(url) { p, m in
                    Task { @MainActor in self.trascrizioni[id]?.progresso = p; self.trascrizioni[id]?.messaggio = m }
                }
                store.salvaTrascrizione(id, testo)
            } catch is CancellationError {
            } catch {
                errori[id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            trascrizioni[id] = nil
            tasks["t\(id)"] = nil
        }
    }

    func riassumi(_ r: Registrazione, in store: RecordingStore) {
        guard riassunti[r.id] == nil else { return }
        let testo = store.trascrizione(r.id)
        if let motivo = LimitiElaborazione.bloccoRiassunto(r, trascrizione: testo) { errori[r.id] = motivo; return }
        guard let testo else { return }
        errori[r.id] = nil
        riassunti[r.id] = Stato(progresso: 0, messaggio: "Preparazione…")
        let id = r.id
        tasks["r\(id)"] = Task {
            do {
                let md = try await AppleIntelligence.riassumi(testo) { p, m in
                    Task { @MainActor in self.riassunti[id]?.progresso = p; self.riassunti[id]?.messaggio = m }
                }
                store.salvaRiassunto(id, md)
            } catch is CancellationError {
            } catch {
                errori[id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            riassunti[id] = nil
            tasks["r\(id)"] = nil
        }
    }

    func annulla(_ tipo: Tipo, _ id: UUID) {
        let prefisso = switch tipo { case .trascrizione: "t"; case .riassunto: "r"; case .miglioramento: "m" }
        let key = prefisso + id.uuidString
        tasks[key]?.cancel()
        tasks[key] = nil
        switch tipo {
        case .trascrizione: trascrizioni[id] = nil
        case .riassunto: riassunti[id] = nil
        case .miglioramento: miglioramenti[id] = nil
        }
    }

    func annullaTutto() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        trascrizioni = [:]
        riassunti = [:]
        miglioramenti = [:]
    }
}
