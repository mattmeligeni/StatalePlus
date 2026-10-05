import Foundation
import Observation
import UIKit

/// Trascrizioni, riassunti e miglioramenti in corso, indipendenti dalla schermata aperta. Girano in
/// `EsecuzioneEstesa`: da iOS 26 continuano anche uscendo dall'app (con l'avanzamento mostrato da iOS).
///
/// - Catena automatica dopo una registrazione: trascrizione → riassunto → miglioramento dell'audio (per l'ascolto),
///   uno dopo l'altro per non contendersi Neural Engine, GPU e CPU.
/// - Pausa e ripresa: GPU (Qwen) e, da iOS 27, Neural Engine (Parakeet) non sono usabili con l'app in background
///   senza entitlement che gli account sviluppatore personali non hanno. Un lavoro che si ferma per questo resta
///   "in pausa" e riparte da solo quando l'app torna in primo piano (Qwen dalle sezioni già scritte).
@Observable
final class ElaborazioniAudio {
    enum Tipo: Hashable { case trascrizione, riassunto, miglioramento }

    struct Stato: Equatable {
        var progresso: Double
        var messaggio: String
        var motore: String? = nil
        var inPausa = false
    }

    private(set) var trascrizioni: [UUID: Stato] = [:]
    private(set) var riassunti: [UUID: Stato] = [:]
    private(set) var miglioramenti: [UUID: Stato] = [:]
    private(set) var errori: [UUID: String] = [:]
    private(set) var erroriMiglioramento: [UUID: String] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// Registrazioni nella catena automatica.
    @ObservationIgnored private var automatiche: Set<UUID> = []
    /// Lavori fermati dal background, da rilanciare al ritorno in primo piano.
    @ObservationIgnored private var daRiprendere: [(Tipo, UUID)] = []
    @ObservationIgnored private weak var archivio: RecordingStore?
    @ObservationIgnored private var osservatori: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        osservatori.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            PrimoPiano.imposta(false)
        })
        osservatori.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            PrimoPiano.imposta(true)
            MainActor.assumeIsolated { self?.riprendi() }
        })
    }

    func stato(_ tipo: Tipo, _ id: UUID) -> Stato? {
        switch tipo {
        case .trascrizione: trascrizioni[id]
        case .riassunto: riassunti[id]
        case .miglioramento: miglioramenti[id]
        }
    }

    // MARK: Catena automatica

    /// Dopo una registrazione: trascrizione e riassunto se attivi in Altro › IA, poi il miglioramento dell'audio.
    func dopoRegistrazione(_ r: Registrazione, in store: RecordingStore) {
        archivio = store
        if Preferenze.elaborazioneAutomatica, LimitiElaborazione.bloccoTrascrizione(r) == nil {
            automatiche.insert(r.id)
            trascrivi(r, in: store)
        } else if Preferenze.miglioraAudio {
            migliora(r, in: store)
        }
    }

    /// Passo successivo della catena (dopo una trascrizione o un riassunto conclusi, anche con errore).
    private func prosegui(dopo tipo: Tipo, _ id: UUID) {
        guard automatiche.contains(id), let store = archivio, let r = store.item(id) else { return }
        switch tipo {
        case .trascrizione where MotoreRiassunto.disponibile != nil
            && LimitiElaborazione.bloccoRiassunto(r, trascrizione: store.trascrizione(id)) == nil:
            riassumi(r, in: store)
        case .trascrizione, .riassunto:
            automatiche.remove(id)
            if Preferenze.miglioraAudio, !store.haOriginale(id) { migliora(r, in: store) }
        case .miglioramento:
            automatiche.remove(id)
        }
    }

    // MARK: Lavori

    /// Volume e rumore di fondo (`MiglioramentoAudio`): l'audio migliorato sostituisce quello della registrazione,
    /// l'originale resta. Non parte mentre la stessa registrazione viene trascritta (e viceversa).
    func migliora(_ r: Registrazione, in store: RecordingStore) {
        guard miglioramenti[r.id] == nil, trascrizioni[r.id] == nil else { return }
        archivio = store
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
        guard trascrizioni[r.id] == nil || trascrizioni[r.id]?.inPausa == true else { return }
        if miglioramenti[r.id] != nil { errori[r.id] = "Attendi la fine del miglioramento dell'audio."; return }
        if let motivo = LimitiElaborazione.bloccoTrascrizione(r) { errori[r.id] = motivo; return }
        archivio = store
        errori[r.id] = nil
        // Parakeet solo se scelto e scaricato; altrimenti Apple.
        let motore: MotoreTrascrizione = Preferenze.motoreTrascrizione == .parakeet && ParakeetLocale.installato ? .parakeet : .apple
        trascrizioni[r.id] = Stato(progresso: 0, messaggio: "Preparazione…", motore: motore.nome)
        let url = store.audioPerTrascrizione(r)
        let id = r.id
        let titolo = r.titolo
        tasks["t\(id)"] = Task {
            do {
                let testo = try await EsecuzioneEstesa.esegui(titolo: "Trascrizione", sottotitolo: titolo) { sistema in
                    try await Trascrittore.trascrivi(url, motore: motore) { p, m in
                        sistema(p, fase: m)
                        Task { @MainActor in self.trascrizioni[id]?.progresso = p; self.trascrizioni[id]?.messaggio = m }
                    }
                }
                store.salvaTrascrizione(id, testo)
            } catch is CancellationError {
                tasks["t\(id)"] = nil
                if trascrizioni[id]?.inPausa != true { trascrizioni[id] = nil }
                return
            } catch {
                if sospendi(.trascrizione, id, error) { return }
                errori[id] = Self.messaggio(error)
            }
            trascrizioni[id] = nil
            tasks["t\(id)"] = nil
            prosegui(dopo: .trascrizione, id)
        }
    }

    func riassumi(_ r: Registrazione, in store: RecordingStore) {
        guard riassunti[r.id] == nil || riassunti[r.id]?.inPausa == true else { return }
        let testo = store.trascrizione(r.id)
        if let motivo = LimitiElaborazione.bloccoRiassunto(r, trascrizione: testo) { errori[r.id] = motivo; return }
        guard let testo, let motore = MotoreRiassunto.disponibile else { return }
        archivio = store
        errori[r.id] = nil
        riassunti[r.id] = Stato(progresso: 0, messaggio: "Preparazione…", motore: motore.nome)
        let id = r.id
        let titolo = r.titolo
        tasks["r\(id)"] = Task {
            do {
                let md = try await EsecuzioneEstesa.esegui(titolo: "Riassunto", sottotitolo: titolo) { sistema in
                    let aggiorna: @Sendable (Double, String) -> Void = { p, m in
                        sistema(p, fase: m)
                        Task { @MainActor in self.riassunti[id]?.progresso = p; self.riassunti[id]?.messaggio = m }
                    }
                    return switch motore {
                    case .qwen: try await QwenLocale.riassumi(testo, progresso: aggiorna)
                    case .apple: try await AppleIntelligence.riassumi(testo, progresso: aggiorna)
                    }
                }
                store.salvaRiassunto(id, md)
            } catch is CancellationError {
                tasks["r\(id)"] = nil
                if riassunti[id]?.inPausa != true { riassunti[id] = nil }
                return
            } catch {
                if sospendi(.riassunto, id, error) { return }
                errori[id] = Self.messaggio(error)
            }
            riassunti[id] = nil
            tasks["r\(id)"] = nil
            prosegui(dopo: .riassunto, id)
        }
    }

    // MARK: Pausa e ripresa

    /// Un errore arrivato con l'app fuori dal primo piano (GPU o Neural Engine non permessi) mette il lavoro in pausa.
    private func sospendi(_ tipo: Tipo, _ id: UUID, _ error: Error) -> Bool {
        let perBackground = (error as? QwenLocale.Errore) == .inPausa || !PrimoPiano.attivo
        guard perBackground else { return false }
        let pausa = Stato(progresso: stato(tipo, id)?.progresso ?? 0, messaggio: "In pausa: riprende quando torni nell'app",
                          motore: stato(tipo, id)?.motore, inPausa: true)
        switch tipo {
        case .trascrizione: trascrizioni[id] = pausa; tasks["t\(id)"] = nil
        case .riassunto: riassunti[id] = pausa; tasks["r\(id)"] = nil
        case .miglioramento: return false
        }
        daRiprendere.append((tipo, id))
        if PrimoPiano.attivo { riprendi() }
        return true
    }

    private func riprendi() {
        guard let store = archivio else { return }
        let lavori = daRiprendere
        daRiprendere = []
        for (tipo, id) in lavori {
            guard let r = store.item(id) else { continue }
            switch tipo {
            case .trascrizione: trascrivi(r, in: store)
            case .riassunto: riassumi(r, in: store)
            case .miglioramento: break
            }
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
        automatiche.remove(id)
        daRiprendere.removeAll { $0 == (tipo, id) }
        switch tipo {
        case .trascrizione: trascrizioni[id] = nil
        case .riassunto: riassunti[id] = nil
        case .miglioramento: miglioramenti[id] = nil
        }
    }

    func annullaTutto() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        automatiche = []
        daRiprendere = []
        trascrizioni = [:]
        riassunti = [:]
        miglioramenti = [:]
    }
}

extension MotoreRiassunto {
    /// Il motore che si userà ora: Qwen se scelto, scaricato e supportato; altrimenti Apple Intelligence se
    /// disponibile; nil se nessuno dei due.
    nonisolated static var disponibile: MotoreRiassunto? {
        if Preferenze.motoreRiassunto == .qwen, QwenLocale.installato, QwenLocale.supportato { return .qwen }
        return AppleIntelligence.stato == .disponibile ? .apple : nil
    }
}
