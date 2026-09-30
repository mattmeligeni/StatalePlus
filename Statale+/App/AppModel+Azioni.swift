import Foundation

enum AppTab: Hashable { case oggi, orario, ariel, registrazioni, altro }
enum AltroRoute: Hashable { case carriera, tasse, esami, aule, presenze, impostazioni, crediti }

extension AppModel {
    // MARK: Presenze

    func loadPresenze() async {
        guard let m = studente?.matricolaAPI else { return }
        await frequenze.load { try await services.easyBadge.frequenze(matricolaAPI: m) }
        let codici = (frequenze.value ?? []).map(\.codice)
        await slotPresenze.load { try await services.easyBadge.slot(matricolaAPI: m, codici: codici) }
        await loadObbligoFrequenza()
    }

    /// Percentuale di frequenza richiesta dal manifesto del proprio corso; si riscarica solo se cambia
    /// l'anno accademico o il corso. In caso di errore resta quella di EasyBadge (o quella scelta in Impostazioni).
    func loadObbligoFrequenza() async {
        guard let s = studente else { return }
        let inizio = Int(Formats.currentAcademicYear().prefix(4)) ?? 0
        let chiave = "\(s.codiceCorso)|\(s.anno)|\(inizio)"
        guard Preferenze.chiaveObbligoFrequenza != chiave || obbligoFrequenza == nil else { return }
        guard let o = try? await services.manifesti.obbligoFrequenza(codiceCorso: s.codiceCorso, annoCorso: s.anno,
                                                                      inizioAnnoAccademico: inizio) else { return }
        obbligoFrequenza = o
        Preferenze.chiaveObbligoFrequenza = chiave
    }

    /// Soglia effettiva per un corso: scelta dall'utente, altrimenti manifesto, altrimenti EasyBadge.
    func soglia(per f: Frequenza, manuale: Int = Preferenze.sogliaManuale) -> (valore: Double, fonte: FonteSoglia) {
        if manuale > 0 { return (Double(manuale) / 100, .utente) }
        if let o = obbligoFrequenza { return (o.soglia, .manifesto) }
        return (f.soglia, .easyBadge)
    }

    // MARK: Registrazioni

    /// Eliminazione completa: ferma le elaborazioni in corso, poi audio, metadati, trascrizione, riassunto e indice.
    func eliminaRegistrazione(_ r: Registrazione) {
        elaborazioni.annulla(.trascrizione, r.id)
        elaborazioni.annulla(.riassunto, r.id)
        recordings.delete(r)
    }

    /// Registrazioni ricostruite senza insegnamento: si cerca nell'orario la lezione in corso a quell'ora
    /// (da 15 minuti prima dell'inizio alla fine) e se ne prende l'insegnamento. Restano "da verificare".
    func assegnaInsegnamentiRecuperati() {
        guard let lezioni = lezioniUtente.value else { return }
        let insegnamenti = agenda?.insegnamentiUtenteAttivati ?? []
        for var r in recordings.items where r.richiedeVerifica && r.codiceInsegnamento == nil && r.insegnamento == nil {
            guard let l = lezioni.first(where: {
                !$0.annullato && $0.inizio.addingTimeInterval(-15 * 60) <= r.creata && r.creata <= $0.fine
            }) else { continue }
            let ins = insegnamenti.first { $0.nome.matchKey == l.insegnamento.matchKey || $0.codice.hasPrefix(l.codiceInsegnamento + "_") }
            let titoloPredefinito = r.titolo == Registrazione.titoloPredefinito(insegnamento: nil, creata: r.creata)
            r.codiceInsegnamento = ins?.codice ?? l.codiceInsegnamento
            r.insegnamento = ins?.nome ?? l.insegnamento
            if titoloPredefinito { r.titolo = Registrazione.titoloPredefinito(insegnamento: r.insegnamento, creata: r.creata) }
            recordings.update(r)
        }
    }

    /// Finestra delle azioni in Oggi: lezione non annullata, da 10 minuti prima dell'inizio fino alla fine.
    static func inFinestraAzioni(_ l: Lezione, now: Date = .now) -> Bool {
        guard !l.annullato, now < l.fine else { return false }
        return Int((l.inizio.timeIntervalSince(now) / 60).rounded(.up)) <= 10
    }

    /// Slot EasyBadge della lezione: stesso insegnamento ("DBD-28" ↔ "DBD-28_1") e orari sovrapposti.
    func slot(per l: Lezione) -> SlotLezione? {
        slotPresenze.value?.first { s in
            (s.codiceCorso == l.codiceInsegnamento || s.codiceCorso.hasPrefix(l.codiceInsegnamento + "_"))
                && s.inizio < l.fine && s.fine > l.inizio
        }
    }

    /// Presenza già registrata: dal server (anche da un altro dispositivo) o da una conferma positiva in questa sessione.
    func presenzaConfermata(_ l: Lezione) -> Bool {
        presenzeConfermate.contains(l.id) || slot(per: l)?.presenza == true
    }

    /// Da chiamare quando il server risponde positivamente a una timbratura.
    func registraPresenzaConfermata(at date: Date = .now) {
        if let t = presenzaTarget { presenzeConfermate.insert(t.id) }
        for l in lezioniUtente.value ?? [] where Self.inFinestraAzioni(l, now: date) { presenzeConfermate.insert(l.id) }
        presenzaTarget = nil
    }

    func insegnamento(per l: Lezione) -> InsegnamentoAgenda? {
        let list = agenda?.insegnamentiUtenteAttivati ?? []
        return list.first { $0.codice.hasPrefix(l.codiceInsegnamento + "_") } ?? list.first { $0.nome.matchKey == l.insegnamento.matchKey }
    }

    // MARK: Azioni da Oggi

    func apriConfermaPresenza(_ l: Lezione) {
        presenzaTarget = l
        altroPath = [.presenze]
        tab = .altro
    }

    /// Porta alla tab Registrazioni e avvia subito la registrazione dell'insegnamento della lezione.
    func avviaRegistrazione(_ l: Lezione) {
        tab = .registrazioni
        guard recorder.state == .idle else { return }
        let ins = insegnamento(per: l)
        registrazioneRichiesta = ins
        Task { await recorder.start(in: recordings, insegnamento: ins) }
    }

    /// Porta alla tab Orario sulla settimana della lezione (tornando al proprio corso se serve).
    func mostraInOrario(_ l: Lezione) {
        if !isMioCorsoOrario, let mio = agenda?.mioCorsoOrario { setCorsoOrario(mio) }
        orarioRichiesta = l
        tab = .orario
    }

    // MARK: Refresh automatico

    static let intervalloRefresh: TimeInterval = 300

    /// Azzera il timer del refresh automatico (chiamato dai pull-to-refresh).
    func segnaRefresh() { ultimoRefresh = .now }

    /// Dati più rilevanti: lezioni di oggi, presenze, orario e prenotazioni (se già aperti).
    func refreshRilevanti() async {
        segnaRefresh()
        async let a: Void = loadLezioniUtente()
        async let b: Void = loadPresenze()
        async let c: Void = orario.updatedAt != nil ? loadOrario() : ()
        async let d: Void = prenotazioni.updatedAt != nil ? loadPrenotazioni() : ()
        _ = await (a, b, c, d)
    }

    /// Ogni 5 minuti dall'ultimo refresh (manuale o automatico), finché l'app è in primo piano.
    func avviaAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.phase == .ready, Date.now.timeIntervalSince(self.ultimoRefresh) >= Self.intervalloRefresh {
                    await self.refreshRilevanti()
                }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func fermaAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: Logout

    /// Rimuove sempre credenziali, cookie e dati dell'account. Con `eliminaDatiLocali` elimina anche
    /// registrazioni, foto profilo, file scaricati e cache; altrimenti li conserva per un altro profilo.
    func logout(eliminaDatiLocali: Bool) {
        if recorder.state != .idle {
            if eliminaDatiLocali { recorder.discard(in: recordings) } else if let r = recorder.stop() { recordings.add(r) }
        }
        fermaAutoRefresh()
        KeychainStore.delete()
        CookieJar.clearUniversityCookies()
        store.wipe()
        resetLive()
        aule.reset(); alberoOrario.reset(); alberoEsami.reset()
        Preferenze.azzera()
        obbligoFrequenza = nil
        if eliminaDatiLocali {
            elaborazioni.annullaTutto()
            recordings.deleteAll()
            photo.remove()
            let fm = FileManager.default
            (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil))?.forEach { try? fm.removeItem(at: $0) }
            URLCache.shared.removeAllCachedResponses()
        }
        tab = .oggi
        altroPath = []
        presenzaTarget = nil
        registrazioneRichiesta = nil
        bootstrapError = nil
        arielError = nil
        phase = .onboarding
    }
}
