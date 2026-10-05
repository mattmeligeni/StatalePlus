import Foundation
import Observation

/// Trascrizioni, riassunti e miglioramenti in corso, indipendenti dalla schermata aperta. Girano in
/// `EsecuzioneEstesa`: da iOS 26 continuano anche uscendo dall'app (con l'avanzamento mostrato da iOS).
@Observable
final class ElaborazioniAudio {
    enum Tipo { case trascrizione, riassunto, miglioramento }

    struct Stato: Equatable {
        var progresso: Double
        var messaggio: String
        var motore: MotoreTrascrizione? = nil
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
        let titolo = r.titolo
        tasks["m\(id)"] = Task {
            do {
                try await EsecuzioneEstesa.esegui(titolo: "Miglioramento audio", sottotitolo: titolo) { sistema in
                    try await store.migliora(id) { p in
                        sistema(p)
                        Task { @MainActor in self.miglioramenti[id]?.progresso = p }
                    }
                }
            } catch is CancellationError {
            } catch {
                erroriMiglioramento[id] = Self.messaggio(error)
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
        // Whisper solo se scelto e scaricato; altrimenti Apple.
        let motore: MotoreTrascrizione = Preferenze.motoreTrascrizione == .whisper && WhisperLocale.installato ? .whisper : .apple
        trascrizioni[r.id] = Stato(progresso: 0, messaggio: "Preparazione…", motore: motore)
        let url = store.url(for: r)
        let id = r.id
        let contesto = [r.insegnamento].compactMap { $0 }
        let titolo = r.titolo
        tasks["t\(id)"] = Task {
            do {
                let testo = try await EsecuzioneEstesa.esegui(titolo: "Trascrizione (\(motore.nome))", sottotitolo: titolo,
                                                                 usaGPU: motore == .whisper) { sistema in
                    try await Trascrittore.trascrivi(url, motore: motore, contesto: contesto) { p, m in
                        sistema(p, fase: m)
                        Task { @MainActor in self.trascrizioni[id]?.progresso = p; self.trascrizioni[id]?.messaggio = m }
                    }
                }
                store.salvaTrascrizione(id, testo)
            } catch is CancellationError {
            } catch {
                errori[id] = Self.messaggio(error)
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
        let titolo = r.titolo
        tasks["r\(id)"] = Task {
            do {
                let md = try await EsecuzioneEstesa.esegui(titolo: "Riassunto", sottotitolo: titolo) { sistema in
                    try await AppleIntelligence.riassumi(testo) { p, m in
                        sistema(p, fase: m)
                        Task { @MainActor in self.riassunti[id]?.progresso = p; self.riassunti[id]?.messaggio = m }
                    }
                }
                store.salvaRiassunto(id, md)
            } catch is CancellationError {
            } catch {
                errori[id] = Self.messaggio(error)
            }
            riassunti[id] = nil
            tasks["r\(id)"] = nil
        }
    }

    private static func messaggio(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
