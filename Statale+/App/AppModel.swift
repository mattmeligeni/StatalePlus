import Foundation
import Observation

/// Stato radice dell'app: onboarding, bootstrap e dati live condivisi fra le tab.
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case onboarding
        case bootstrapping(String)
        case ready
    }

    var phase: Phase = .launching
    var bootstrapError: String?
    var arielError: String?

    let services = AppServices()
    let store = StableStore()
    let photo = ProfilePhoto()
    let recordings = RecordingStore()
    let recorder = AudioRecorder()

    // Dati live condivisi
    let lezioniUtente = Live<[Lezione]>()          // Oggi, Registrazioni: corso dell'utente, insegnamenti attivati
    let orario = Live<[Lezione]>()                 // tab Orario: corso + periodo scelti
    let insegnamentiOrario = Live<[InsegnamentoAgenda]>()
    let appelli = Live<[Appello]>()                // Esami › Calendario: corso + anno scelti
    let appelliUtente = Live<[Appello]>()          // arricchisce le prenotazioni (aula/sede)
    let prenotazioni = Live<TabellaSifa>()
    let aule = Live<OccupazioneAule>()
    let alberoOrario = Live<[AgendaScuola]>()
    let alberoEsami = Live<[AgendaScuola]>()
    let frequenze = Live<[Frequenza]>()            // Presenze
    let slotPresenze = Live<[SlotLezione]>()       // Presenze, pulsante "Conferma presenza" in Oggi

    // Navigazione
    var tab: AppTab = .oggi
    var altroPath: [AltroRoute] = []
    /// Lezione per cui l'utente ha aperto "Conferma presenza" da Oggi.
    var presenzaTarget: Lezione?
    /// Insegnamento da registrare, impostato da "Inizia registrazione" in Oggi.
    var registrazioneRichiesta: InsegnamentoAgenda?
    /// Lezioni per cui il server ha confermato la presenza in questa sessione.
    var presenzeConfermate: Set<String> = []

    // Refresh automatico
    var ultimoRefresh: Date = .now
    @ObservationIgnored var autoRefreshTask: Task<Void, Never>?

    var studente: Studente? { store.snapshot.studente }
    var agenda: AgendaConfig? { store.snapshot.agenda }
    var email: String? { KeychainStore.load()?.email }

    // MARK: Avvio

    func start() async {
        guard phase == .launching else { return }
        guard KeychainStore.load() != nil else { phase = .onboarding; return }
        if studente != nil, agenda != nil {
            phase = .ready
            await refreshStableIfNeeded()
        } else {
            await bootstrap()
        }
    }

    /// Le credenziali vanno in Keychain dopo un login CAS riuscito.
    func login(email: String, password: String) async {
        bootstrapError = nil
        let creds = Credentials(email: email.trimmed.lowercased(), password: password)
        phase = .bootstrapping("Accesso con le credenziali di Ateneo…")
        do {
            try await services.cas.ensureLoggedIn(with: creds)
            try KeychainStore.save(creds)
        } catch {
            bootstrapError = message(error)
            phase = .onboarding
            return
        }
        await bootstrap()
    }

    /// UNIMIA → matricola e codice corso → configurazione Agenda. Login Ariel in parallelo.
    func bootstrap() async {
        phase = .bootstrapping("Lettura del profilo da UNIMIA…")
        async let arielLogin: Void = loginAriel()
        do {
            let (s, _) = try await services.unimia.profilo()
            store.update { $0.studente = s; $0.profiloAggiornato = .now }
            phase = .bootstrapping("Configurazione di orario ed esami…")
            let cfg = try await services.agenda.configura(codiceCorso: s.codiceCorso, anno: s.anno, precedente: agenda)
            store.update { $0.agenda = cfg }
            await arielLogin
            resetLive()
            phase = .ready
        } catch {
            await arielLogin
            bootstrapError = message(error)
            phase = studente != nil && agenda != nil ? .ready : .onboarding
        }
    }

    private func loginAriel() async {
        do {
            try await services.arielSession.ensureLoggedIn()
            arielError = nil
        } catch {
            arielError = message(error)
        }
    }

    /// Aggiornamento manuale di profilo e configurazione, senza passare dalla schermata di bootstrap.
    func aggiornaProfilo() async throws {
        let (s, _) = try await services.unimia.profilo()
        store.update { $0.studente = s; $0.profiloAggiornato = .now }
        let cfg = try await services.agenda.configura(codiceCorso: s.codiceCorso, anno: s.anno, precedente: agenda)
        store.update { $0.agenda = cfg }
        resetLive()
    }

    func refreshStableIfNeeded() async {
        if store.isStale(store.snapshot.profiloAggiornato, ttl: StableStore.ttlProfilo),
           let (s, _) = try? await services.unimia.profilo() {
            store.update { $0.studente = s; $0.profiloAggiornato = .now }
        }
        if let s = studente, store.isStale(agenda?.aggiornato, ttl: StableStore.ttlAgenda),
           let cfg = try? await services.agenda.configura(codiceCorso: s.codiceCorso, anno: s.anno, precedente: agenda) {
            store.update { $0.agenda = cfg }
        }
    }

    // MARK: Orario

    var periodoOrario: AgendaPeriodo? {
        guard let a = agenda else { return nil }
        let periodi = a.corsoOrario.cdl.periodi
        return a.periodoOrario.flatMap { id in periodi.first { $0.id == id } } ?? AgendaConfig.periodoAttuale(periodi)
    }

    var isMioCorsoOrario: Bool { agenda.map { $0.corsoOrario.cdl.valore == $0.mioCorsoOrario.cdl.valore } ?? true }

    /// Insegnamenti attivati per un corso; senza scelta salvata: anno dello studente (suo corso) o 1° anno.
    func attivati(cdl: AgendaCdl, insegnamenti: [InsegnamentoAgenda]) -> Set<String> {
        if let s = agenda?.attivati[cdl.valore] { return s }
        let anno = cdl.valore == agenda?.mioCorsoOrario.cdl.valore ? String(agenda?.annoStudente ?? 1) : "1"
        return Set(insegnamenti.filter { $0.anno == anno }.map(\.codice))
    }

    func loadOrario(refreshInsegnamenti: Bool = false) async {
        guard let a = agenda, let p = periodoOrario else { return }
        let cdl = a.corsoOrario.cdl
        let key = AgendaConfig.key(cdl.valore, p.id)
        await orario.load {
            var list = a.insegnamenti[key]
            if list == nil || refreshInsegnamenti {
                let fresh = try await services.agenda.insegnamenti(cdl: cdl, periodo: p.id)
                store.update { $0.agenda?.insegnamenti[key] = fresh }
                list = fresh
            }
            let all = list ?? []
            insegnamentiOrario.set(all)
            let on = attivati(cdl: cdl, insegnamenti: all)
            return try await services.agenda.lezioni(di: all.filter { on.contains($0.codice) })
        }
    }

    func setCorsoOrario(_ c: CorsoSelezionato) {
        store.update { $0.agenda?.corsoOrario = c; $0.agenda?.periodoOrario = nil }
        orario.reset(); insegnamentiOrario.reset()
    }

    func setPeriodoOrario(_ id: String) {
        store.update { $0.agenda?.periodoOrario = id }
        orario.reset(); insegnamentiOrario.reset()
    }

    func setAttivati(cdl: String, _ codici: Set<String>) {
        store.update { $0.agenda?.attivati[cdl] = codici }
        if cdl == agenda?.mioCorsoOrario.cdl.valore { lezioniUtente.reset() }
    }

    /// Lezioni del corso dell'utente (insegnamenti attivati, tutti i periodi).
    func loadLezioniUtente() async {
        guard let list = agenda?.insegnamentiUtenteAttivati else { return }
        await lezioniUtente.load { try await services.agenda.lezioni(di: list) }
    }

    // MARK: Esami

    var annoEsami: AgendaPeriodo? {
        guard let a = agenda else { return nil }
        let periodi = a.corsoEsami.cdl.periodi
        if let v = a.annoEsami, let p = periodi.first(where: { $0.valore == v }) { return p }
        if a.corsoEsami.cdl.valore == a.mioCorsoEsami.cdl.valore, let p = periodi.first(where: { $0.valore == String(a.annoStudente) }) { return p }
        return periodi.first
    }

    func loadAppelli() async {
        guard let a = agenda, let anno = annoEsami else { return }
        await appelli.load { try await services.agenda.appelli(codiceCorso: a.corsoEsami.cdl.codiceLettera, anni: [anno.valore]) }
    }

    func setCorsoEsami(_ c: CorsoSelezionato) {
        store.update { $0.agenda?.corsoEsami = c; $0.agenda?.annoEsami = nil }
        appelli.reset()
    }

    func setAnnoEsami(_ valore: String) {
        store.update { $0.agenda?.annoEsami = valore }
        appelli.reset()
    }

    func loadPrenotazioni() async {
        await prenotazioni.load { try await services.sifa.prenotazioni() }
    }

    func loadAppelliUtente() async {
        guard let a = agenda else { return }
        await appelliUtente.load {
            try await services.agenda.appelli(codiceCorso: a.codiceCorso, anni: a.mioCorsoEsami.cdl.periodi.map(\.valore))
        }
    }

    /// Prossimo appello fra quelli prenotati, arricchito con aula/sede dal calendario Agenda.
    var prossimoAppelloPrenotato: (prenotazione: Prenotazione, appello: Appello?)? {
        guard let tab = prenotazioni.value else { return nil }
        let oggi = Formats.calendar.startOfDay(for: .now)
        guard let p = Prenotazione.from(tab).first(where: { $0.data >= oggi }) else { return nil }
        let match = appelliUtente.value?.first {
            Formats.calendar.isDate($0.inizio, inSameDayAs: p.data)
                && ($0.insegnamento.matchKey.contains(p.esame.matchKey) || p.esame.matchKey.contains($0.insegnamento.matchKey))
        }
        return (p, match)
    }

    // MARK: Aule e mappe

    func loadAule(force: Bool = false) async {
        if force { await aule.load { try await services.easyRoom.occupazioneOggi() } }
        else { await aule.loadIfNeeded { try await services.easyRoom.occupazioneOggi() } }
    }

    /// Indirizzo dell'aula da EasyRoom (per codice, poi per nome aula + sede, poi per sede); ricerca libera come ultima risorsa.
    func mapsURL(aula: String, sede: String, codici: [String] = []) async -> URL? {
        await loadAule()
        if let occ = aule.value {
            if let a = occ.aula(codici: codici, nome: aula, sede: sede) { return Maps.url(address: a.indirizzo) }
            if let s = occ.sede(nome: sede) { return Maps.url(address: s.indirizzo) }
        }
        return Maps.url(address: "\(aula), \(sede), Milano")
    }

    // MARK: Alberi corsi

    func loadAlberoOrario() async { await alberoOrario.loadIfNeeded { try await services.agenda.alberoOrario() } }
    func loadAlberoEsami() async { await alberoEsami.loadIfNeeded { try await services.agenda.alberoEsami() } }

    // MARK: Logout

    func resetLive() {
        lezioniUtente.reset(); orario.reset(); appelli.reset(); appelliUtente.reset()
        insegnamentiOrario.reset(); prenotazioni.reset(); frequenze.reset(); slotPresenze.reset()
        presenzeConfermate = []
    }

    func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// Apre Mappe sull'indirizzo.
nonisolated enum Maps {
    static func url(address: String) -> URL? {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [.init(name: "q", value: address)]
        return c.url
    }
}
