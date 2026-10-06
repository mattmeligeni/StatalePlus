import Foundation
import Observation
import OSLog
import UIKit

/// Trascrizioni, riassunti e miglioramenti in corso, indipendenti dalla schermata aperta. Girano in
/// `EsecuzioneEstesa`: da iOS 26 continuano anche uscendo dall'app (con l'avanzamento mostrato da iOS).
///
/// - Catena automatica dopo una registrazione: trascrizione → riassunto → miglioramento dell'audio (per l'ascolto),
///   uno dopo l'altro per non contendersi Neural Engine, GPU e CPU.
/// - Pausa e ripresa: da iOS 27 il Neural Engine (Parakeet) in background richiede l'entitlement "Background
///   Inference". Senza, un lavoro che si ferma uscendo dall'app resta "in pausa" e riparte da solo quando l'app torna
///   in primo piano. Apple Intelligence gira in un processo di sistema e continua anche in background.
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
    /// Correzione delle trascrizioni con il glossario del corso (impostata da `AppModel`).
    @ObservationIgnored var correggiTesto: (String) -> String = { $0 }
    /// Termini del glossario del corso, passati ai riassunti (impostati da `AppModel`).
    @ObservationIgnored var terminiGlossario: () -> [String] = { [] }
    /// Termini riconosciuti in una lezione riassunta → glossario; restituisce quanti sono nuovi (impostato da `AppModel`).
    @ObservationIgnored var imparaTermini: ([String], String) -> Int = { _, _ in 0 }
    /// Identificativo dell'ultimo lavoro avviato per ogni chiave ("t"/"r"/"m" + id della registrazione). Un lavoro
    /// annullato o sostituito può finire più tardi (il caricamento di un modello non si interrompe): confrontando il
    /// suo identificativo con questo non tocca più lo stato né salva risultati. Prima un lavoro annullato, finendo,
    /// cancellava lo stato di quello rilanciato: l'interfaccia tornava a "Trascrivi" mentre la trascrizione andava
    /// avanti nell'attività di sistema.
    @ObservationIgnored private var generazioni: [String: UUID] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.mattiameligeni.StatalePlus", category: "elaborazioni")

    init() {
        let nc = NotificationCenter.default
        osservatori.append(nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            PrimoPiano.imposta(false)
            EsecuzioneEstesa.traccia("App fuori dal primo piano")
        })
        osservatori.append(nc.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { _ in
            EsecuzioneEstesa.traccia("Schermo bloccato (dati protetti non disponibili)")
        })
        osservatori.append(nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            ParakeetLocale.libera()
        })
        osservatori.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            PrimoPiano.imposta(true)
            EsecuzioneEstesa.traccia("App in primo piano")
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
        let (chiave, gen) = nuovoLavoro(.miglioramento, id)
        tasks[chiave] = Task {
            do {
                try await EsecuzioneEstesa.esegui(titolo: "Miglioramento audio", sottotitolo: titolo) { sistema in
                    try await store.migliora(id) { p in
                        sistema(p)
                        Task { @MainActor in if self.corrente(chiave, gen) { self.miglioramenti[id]?.progresso = p } }
                    }
                }
            } catch {
                guard corrente(chiave, gen) else { return }
                if !(error is CancellationError) { erroriMiglioramento[id] = Self.messaggio(error) }
            }
            guard corrente(chiave, gen) else { return }
            miglioramenti[id] = nil
            chiudi(chiave)
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
        let (chiave, gen) = nuovoLavoro(.trascrizione, id)
        tasks[chiave] = Task {
            do {
                let testo = try await EsecuzioneEstesa.esegui(titolo: "Trascrizione", sottotitolo: titolo) { sistema in
                    try await Trascrittore.trascrivi(url, motore: motore) { p, m in
                        sistema(p, fase: m)
                        Task { @MainActor in
                            guard self.corrente(chiave, gen) else { return }
                            self.trascrizioni[id]?.progresso = p
                            self.trascrizioni[id]?.messaggio = m
                        }
                    }
                }
                guard corrente(chiave, gen) else { return }
                store.salvaTrascrizione(id, correggiTesto(testo.testo))
                store.salvaTempi(id, testo.ancore)
            } catch {
                guard corrente(chiave, gen) else { return }
                EsecuzioneEstesa.traccia("Trascrizione non riuscita (\(motore.rawValue), in primo piano: \(PrimoPiano.attivo)): \(String(describing: error))", errore: true)
                if sospendi(.trascrizione, id, error) { return }
                errori[id] = error is CancellationError ? Self.interrotto : Self.messaggio(error)
            }
            trascrizioni[id] = nil
            chiudi(chiave)
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
        let glossario = terminiGlossario()
        let id = r.id
        let titolo = r.titolo
        let (chiave, gen) = nuovoLavoro(.riassunto, id)
        tasks[chiave] = Task {
            do {
                let md = try await EsecuzioneEstesa.esegui(titolo: "Riassunto", sottotitolo: titolo) { sistema in
                    let aggiorna: @Sendable (Double, String) -> Void = { p, m in
                        sistema(p, fase: m)
                        Task { @MainActor in
                            guard self.corrente(chiave, gen) else { return }
                            self.riassunti[id]?.progresso = p
                            self.riassunti[id]?.messaggio = m
                        }
                    }
                    switch motore {
                    case .apple:
                        return try await AppleIntelligence.riassumi(testo, glossario: glossario, progresso: aggiorna)
                    case .cloud:
                        do {
                            return try await NuvolaApple.riassumi(testo, glossario: glossario, progresso: aggiorna)
                        } catch where NuvolaApple.convieneRipiegare(error) && AppleIntelligence.stato == .disponibile {
                            // Senza rete o oltre il limite giornaliero: si continua sul telefono.
                            Task { @MainActor in if self.corrente(chiave, gen) { self.riassunti[id]?.motore = MotoreRiassunto.apple.nome } }
                            return try await AppleIntelligence.riassumi(testo, glossario: glossario, progresso: aggiorna)
                        }
                    }
                }
                guard corrente(chiave, gen) else { return }
                store.salvaRiassunto(id, md.testo)
                // Il glossario impara i termini della lezione; con quelli nuovi si ricorregge la trascrizione.
                if imparaTermini(md.termini, testo) > 0 {
                    let corretto = correggiTesto(testo)
                    if corretto != testo { store.salvaTrascrizione(id, corretto) }
                }
            } catch {
                guard corrente(chiave, gen) else { return }
                log.error("Riassunto non riuscito (\(motore.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")
                if sospendi(.riassunto, id, error) { return }
                errori[id] = error is CancellationError ? Self.interrotto : Self.messaggio(error)
            }
            riassunti[id] = nil
            chiudi(chiave)
            prosegui(dopo: .riassunto, id)
        }
    }

    private static func chiave(_ tipo: Tipo, _ id: UUID) -> String {
        let prefisso = switch tipo { case .trascrizione: "t"; case .riassunto: "r"; case .miglioramento: "m" }
        return prefisso + id.uuidString
    }

    /// Registra un nuovo lavoro: da qui in poi solo lui aggiorna lo stato di quella registrazione.
    private func nuovoLavoro(_ tipo: Tipo, _ id: UUID) -> (chiave: String, gen: UUID) {
        let chiave = Self.chiave(tipo, id)
        let gen = UUID()
        generazioni[chiave] = gen
        return (chiave, gen)
    }

    private func corrente(_ chiave: String, _ gen: UUID) -> Bool { generazioni[chiave] == gen }

    private func chiudi(_ chiave: String) {
        tasks[chiave] = nil
        generazioni[chiave] = nil
    }

    // MARK: Pausa e ripresa

    /// Un errore arrivato con l'app fuori dal primo piano (Neural Engine non permesso, limiti di Apple Intelligence
    /// in background) mette il lavoro in pausa.
    private func sospendi(_ tipo: Tipo, _ id: UUID, _ error: Error) -> Bool {
        guard !PrimoPiano.attivo else { return false }
        EsecuzioneEstesa.traccia("In pausa fino al ritorno nell'app: \(String(describing: error))")
        let pausa = Stato(progresso: stato(tipo, id)?.progresso ?? 0, messaggio: "In pausa: riprende quando torni nell'app",
                          motore: stato(tipo, id)?.motore, inPausa: true)
        switch tipo {
        case .trascrizione: trascrizioni[id] = pausa
        case .riassunto: riassunti[id] = pausa
        case .miglioramento: return false
        }
        chiudi(Self.chiave(tipo, id))
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

    private static let interrotto = "Interrotto da iOS prima della fine. Riprova tenendo l'app aperta."

    private static func messaggio(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Annullato dall'utente: il lavoro si ferma appena può, e quando finisce non tocca più nulla (generazione tolta).
    func annulla(_ tipo: Tipo, _ id: UUID) {
        let chiave = Self.chiave(tipo, id)
        tasks[chiave]?.cancel()
        chiudi(chiave)
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
        generazioni = [:]
        automatiche = []
        daRiprendere = []
        trascrizioni = [:]
        riassunti = [:]
        miglioramenti = [:]
    }
}

extension MotoreRiassunto {
    /// Il motore che si userà ora: Apple Intelligence online se scelta (è la predefinita) e disponibile; altrimenti
    /// quella sul telefono; nil se nessuna delle due.
    nonisolated static var disponibile: MotoreRiassunto? {
        if Preferenze.motoreRiassunto == .cloud, NuvolaApple.stato == .disponibile { return .cloud }
        return AppleIntelligence.stato == .disponibile ? .apple : nil
    }
}

/// L'app è in primo piano? Serve a distinguere i lavori fermati da iOS uscendo dall'app (da riprendere) dagli errori.
nonisolated enum PrimoPiano {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var valore = true

    static var attivo: Bool {
        lock.lock(); defer { lock.unlock() }
        return valore
    }

    static func imposta(_ v: Bool) {
        lock.lock(); valore = v; lock.unlock()
    }
}
