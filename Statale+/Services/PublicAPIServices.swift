import Foundation

/// API mobili pubbliche su orari-be.divsi.unimi.it: nessuna autenticazione, nessun cookie.
nonisolated private let publicBase = "https://orari-be.divsi.unimi.it"

// MARK: - Agenda Studenti (orario + appelli)

actor AgendaService {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    private func data(_ url: URL) async throws -> Data {
        let r = try await http.get(url, headers: ["Accept": "application/json, text/xml, */*"])
        guard r.status == 200 else { throw NetError.http(r.status) }
        return r.data
    }

    /// Albero orario: scuola → tipo → corso → periodi didattici.
    func alberoOrario() async throws -> [AgendaScuola] {
        try AgendaParser.alberoCorsi(try await data(URL(string: "\(publicBase)/agendastudenti/api_profilo_aa_scuola_tipo_cdl_pd.php")!))
    }

    /// Albero esami: scuola → tipo → corso → anni di corso.
    func alberoEsami() async throws -> [AgendaScuola] {
        try AgendaParser.alberoCorsi(try await data(URL(string: "\(publicBase)/agendastudenti/api_profilo_esami_scuola_tipo_cdl.php")!))
    }

    func insegnamenti(cdl: AgendaCdl, periodo: String) async throws -> [InsegnamentoAgenda] {
        var c = URLComponents(string: "\(publicBase)/agendastudenti/api_profilo_lista_insegnamenti.php")!
        c.queryItems = [.init(name: "cdl", value: cdl.valore), .init(name: "periodo_didattico", value: periodo)]
        let list = try AgendaParser.insegnamenti(try await data(c.url!))
        let code = cdl.codiceLettera
        return list.filter { $0.codiceCdl == code || code.isEmpty }
    }

    /// Configurazione iniziale dal codice corso UNIMIA ("DBD"): corso negli alberi orario ed esami,
    /// insegnamenti di tutti i periodi, insegnamenti attivati (default: anno dello studente).
    func configura(codiceCorso: String, anno: Int, precedente: AgendaConfig?) async throws -> AgendaConfig {
        func trova(_ tree: [AgendaScuola], _ match: (AgendaCdl) -> Bool) -> CorsoSelezionato? {
            for s in tree { for l in s.lauree { if let c = l.cdl.first(where: match) { return CorsoSelezionato(scuola: s.label, tipo: l.tipo, cdl: c) } } }
            return nil
        }
        guard let mioOrario = trova(try await alberoOrario(), { $0.code == codiceCorso }) else {
            throw NetError.unexpectedPage("Agenda: corso \(codiceCorso) non trovato")
        }
        let mioEsami = trova(try await alberoEsami(), { $0.valore == codiceCorso })
            ?? CorsoSelezionato(scuola: mioOrario.scuola, tipo: mioOrario.tipo,
                                cdl: AgendaCdl(label: mioOrario.cdl.label, valore: codiceCorso, code: nil,
                                               periodi: [AgendaPeriodo(label: "\(anno) anno", valore: String(anno), id: String(anno))],
                                               codiceFacolta: mioOrario.cdl.codiceFacolta))

        var cache = precedente?.insegnamenti ?? [:]
        for p in mioOrario.cdl.periodi {
            cache[AgendaConfig.key(mioOrario.cdl.valore, p.id)] = try await insegnamenti(cdl: mioOrario.cdl, periodo: p.id)
        }
        var attivati = precedente?.attivati ?? [:]
        let miei = cache.filter { $0.key.hasPrefix(mioOrario.cdl.valore + "|") }.values.flatMap { $0 }
        if attivati[mioOrario.cdl.valore]?.intersection(Set(miei.map(\.codice))).isEmpty ?? true {
            attivati[mioOrario.cdl.valore] = Set(miei.filter { $0.anno == String(anno) }.map(\.codice))
        }
        return AgendaConfig(codiceCorso: codiceCorso, annoStudente: anno,
                            mioCorsoOrario: mioOrario, mioCorsoEsami: mioEsami,
                            corsoOrario: precedente?.corsoOrario ?? mioOrario, periodoOrario: precedente?.periodoOrario,
                            corsoEsami: precedente?.corsoEsami ?? mioEsami, annoEsami: precedente?.annoEsami,
                            insegnamenti: cache, attivati: attivati, aggiornato: .now)
    }

    /// Orario = unione degli XML degli insegnamenti.
    func lezioni(di insegnamenti: [InsegnamentoAgenda]) async throws -> [Lezione] {
        var out: [Lezione] = []
        for ins in insegnamenti { out += try await lezioni(file: ins.file) }
        return out.sorted { $0.inizio < $1.inizio }
    }

    func lezioni(file: String) async throws -> [Lezione] {
        var c = URLComponents(string: "\(publicBase)/agendastudenti//App/zipped.php")!
        c.queryItems = [.init(name: "file", value: file)]
        return try AgendaParser.orario(try await data(c.url!)).lezioni
    }

    /// Appelli. `esami_cdl[]=DBD|1` va codificato come `esami_cdl%5B%5D=DBD%7C1`.
    func appelli(codiceCorso: String, anni: [String], da: Date = .now, giorni: Int = 240) async throws -> [Appello] {
        guard !anni.isEmpty else { return [] }
        let a = Formats.dmyString(da)
        let b = Formats.dmyString(Formats.calendar.date(byAdding: .day, value: giorni, to: da) ?? da)
        let cdl = anni.map { "esami_cdl%5B%5D=\(codiceCorso)%7C\($0)" }.joined(separator: "&")
        var c = URLComponents(string: "\(publicBase)/agendastudenti/test_call.php")!
        c.percentEncodedQuery = "view=easytest&include=et_cdl&et_er=1&datefrom=\(a)&dateto=\(b)&\(cdl)"
        return try AgendaParser.appelli(try await data(c.url!))
    }
}

// MARK: - EasyRoom (aule)

actor EasyRoomService {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    func occupazioneOggi() async throws -> OccupazioneAule {
        let r = try await http.get(URL(string: "\(publicBase)/EasyRoom/do.php")!)
        guard r.status == 200 else { throw NetError.http(r.status) }
        return try EasyRoomParser.parse(r.data, day: .now)
    }
}

// MARK: - EasyBadge (presenze)

actor EasyBadgeService {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    private struct MatricolaBody: Encodable, Sendable { let Matricola: String }
    private struct SlotBody: Encodable, Sendable {
        let Matricola: String
        let Corsi: [Corso]
        struct Corso: Encodable, Sendable { let codice: String }
    }

    func frequenze(matricolaAPI: String) async throws -> [Frequenza] {
        let r = try await http.postJSON(URL(string: "\(publicBase)/easybadge-new/api/corso_iscritti.php")!,
                                        body: MatricolaBody(Matricola: matricolaAPI))
        return try EasyBadgeParser.frequenze(r.data)
    }

    func slot(matricolaAPI: String, codici: [String]) async throws -> [SlotLezione] {
        guard !codici.isEmpty else { return [] }
        let r = try await http.postJSON(URL(string: "\(publicBase)/easybadge-new/api/timbrature.php")!,
                                        body: SlotBody(Matricola: matricolaAPI, Corsi: codici.map { .init(codice: $0) }))
        return try EasyBadgeParser.slot(r.data)
    }

    /// Timbratura: restituisce `result`/`message` così come arrivano dal server.
    func timbra(_ request: TimbraturaRequest) async throws -> TimbraturaResult {
        let r = try await http.postJSON(URL(string: "\(publicBase)/easybadge-new/api/TimbratureApi.php")!, body: request)
        print(request)
        if let parsed = try? EasyBadgeParser.esitoTimbratura(r.data) { return parsed }
        return TimbraturaResult(result: "HTTP \(r.status)", message: r.text.trimmed.isEmpty ? "Risposta vuota dal server." : r.text.trimmed)
    }
}
