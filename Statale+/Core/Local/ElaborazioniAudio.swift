import Foundation
import Observation

/// Trascrizioni e riassunti in corso, indipendenti dalla schermata aperta (si può uscire dal dettaglio).
@Observable
final class ElaborazioniAudio {
    enum Tipo { case trascrizione, riassunto }

    struct Stato: Equatable {
        var progresso: Double
        var messaggio: String
    }

    private(set) var trascrizioni: [UUID: Stato] = [:]
    private(set) var riassunti: [UUID: Stato] = [:]
    private(set) var errori: [UUID: String] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    func stato(_ tipo: Tipo, _ id: UUID) -> Stato? { tipo == .trascrizione ? trascrizioni[id] : riassunti[id] }

    func trascrivi(_ r: Registrazione, in store: RecordingStore) {
        guard trascrizioni[r.id] == nil else { return }
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
        guard riassunti[r.id] == nil, let testo = store.trascrizione(r.id) else { return }
        errori[r.id] = nil
        riassunti[r.id] = Stato(progresso: 0, messaggio: "Preparazione…")
        let titolo = r.insegnamento ?? r.titolo
        let id = r.id
        tasks["r\(id)"] = Task {
            do {
                let md = try await AppleIntelligence.riassumi(testo, titolo: titolo) { p, m in
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
        let key = (tipo == .trascrizione ? "t" : "r") + id.uuidString
        tasks[key]?.cancel()
        tasks[key] = nil
        if tipo == .trascrizione { trascrizioni[id] = nil } else { riassunti[id] = nil }
    }

    func annullaTutto() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        trascrizioni = [:]
        riassunti = [:]
    }
}
