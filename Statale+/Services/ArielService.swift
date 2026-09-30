import Foundation

/// Ariel (Moodle)
actor ArielService {
    private let session: ArielSession
    private static let moodle = ArielSession.moodle

    init(session: ArielSession) { self.session = session }

    /// Offerta dell'a.a. corrente da https://ariel.unimi.it/Offerta/myof (NON la dashboard Moodle, che è lo storico).
    func offerta(annoAccademico: String = Formats.currentAcademicYear()) async throws -> [InsegnamentoOfferta] {
        let r = try await session.page(URL(string: "https://ariel.unimi.it/Offerta/myof")!)
        return try ArielParser.offerta(r.text, annoAccademico: annoAccademico)
    }

    func struttura(courseId: String) async throws -> CourseState {
        try await session.courseState(courseId: courseId)
    }

    func scheda(courseId: String) async throws -> SchedaInsegnamento? {
        let r = try await session.page(URL(string: "\(Self.moodle)/course/view.php?id=\(courseId)")!)
        return try ArielParser.scheda(r.text)
    }

    func modulo(_ module: CourseState.Module) async throws -> ModuloDettaglio {
        guard let s = module.url, let url = URL(string: s), url.host() == "myariel.unimi.it" else {
            return ModuloDettaglio(descrizione: "", file: [], discussioni: [])
        }
        return try ArielParser.modulo(try await session.page(url).text)
    }

    func discussione(_ d: DiscussioneForum) async throws -> [PostForum] {
        try ArielParser.posts(try await session.page(d.url).text)
    }

    func partecipanti(courseId: String) async throws -> [Partecipante] {
        let r = try await session.page(URL(string: "\(Self.moodle)/user/index.php?id=\(courseId)")!)
        return try ArielParser.partecipanti(r.text)
    }

    func valutazioni(courseId: String) async throws -> [VoceValutazione] {
        let r = try await session.page(URL(string: "\(Self.moodle)/grade/report/index.php?id=\(courseId)")!)
        return try ArielParser.valutazioni(r.text)
    }

    func scarica(_ file: FileMoodle) async throws -> URL {
        try await session.download(file)
    }

    // MARK: Calendario e notifiche

    /// Prossimi eventi di tutti i corsi (vista "Prossimi eventi" del calendario, ~21 giorni) più le attività da fare
    /// già scadute (consegne in ritardo), senza doppioni.
    func scadenze() async throws -> [EventoMoodle] {
        struct Prossimi: Encodable, Sendable { let courseid = 1; let categoryid = 0 }
        struct DaFare: Encodable, Sendable { let timesortfrom: Int; let limitnum = 50 }
        struct Eventi: Decodable { let events: [EventoMoodle] }
        let prossimi = try JSONDecoder().decode(Eventi.self, from: try await session.ajax("core_calendar_get_calendar_upcoming_view", args: Prossimi())).events
        let daFare = (try? JSONDecoder().decode(Eventi.self, from: try await session.ajax(
            "core_calendar_get_action_events_by_timesort",
            args: DaFare(timesortfrom: Int(Date.now.addingTimeInterval(-30 * 86400).timeIntervalSince1970))))).map(\.events) ?? []
        var visti = Set<Int>()
        return (daFare.filter(\.scaduto) + prossimi)
            .filter { visti.insert($0.id).inserted }
            .sorted { $0.inizio < $1.inizio }
    }

    func notifiche(limite: Int = 30) async throws -> NotificheMoodle {
        struct Args: Encodable, Sendable { let useridto = 0; let limit: Int; let offset = 0; let newestfirst = true }
        return try JSONDecoder().decode(NotificheMoodle.self, from: try await session.ajax("message_popup_get_popup_notifications", args: Args(limit: limite)))
    }

    /// Come aprire la notifica sul sito: la segna letta.
    func segnaLetta(_ n: NotificaMoodle) async {
        struct Args: Encodable, Sendable { let notificationid: Int; let timeread: Int }
        _ = try? await session.ajax("core_message_mark_notification_read",
                                    args: Args(notificationid: n.id, timeread: Int(Date.now.timeIntervalSince1970)))
    }

    // MARK: Contenuti del corso

    /// Zip di tutti i materiali ("Scaricamento contenuti del corso"). Il `contextid` è nel link della pagina del corso;
    /// se manca, il docente non ha abilitato lo scaricamento.
    func scaricaContenuti(courseId: String, titolo: String) async throws -> URL {
        let pagina = try await session.page(URL(string: "\(Self.moodle)/course/view.php?id=\(courseId)")!)
        guard let contextId = pagina.text.firstMatch(#"downloadcontent\.php\?contextid=(\d+)"#) else {
            throw ArielError.messaggio("Lo scaricamento dei contenuti non è disponibile per questo corso.")
        }
        let nome = titolo.replacingOccurrences(of: #"[/:\\?%*|"<>]"#, with: "-", options: .regularExpression)
            .collapsed.prefix(80) + ".zip"
        let cartella = URL.cachesDirectory.appending(path: "Materiali/\(courseId)", directoryHint: .isDirectory)
        return try await session.scaricaContenuti(contextId: contextId, nome: String(nome), in: cartella)
    }

    /// Avvisi recenti per la tab Oggi: discussioni dei forum dei corsi attivi, più recenti di `since`.
    func avvisiRecenti(corsi: [InsegnamentoOfferta], since: Date) async -> [(corso: InsegnamentoOfferta, discussione: DiscussioneForum)] {
        var out: [(InsegnamentoOfferta, DiscussioneForum)] = []
        for corso in corsi {
            guard let id = corso.courseId, let state = try? await struttura(courseId: id) else { continue }
            for forum in state.cm where forum.module == "forum" && (forum.uservisible ?? forum.visible) {
                guard let dettaglio = try? await modulo(forum) else { continue }
                for d in dettaglio.discussioni where (d.ultimaAttivita ?? d.creata ?? .distantPast) >= since {
                    out.append((corso, d))
                }
            }
        }
        return out.sorted { ($0.1.ultimaAttivita ?? .distantPast) > ($1.1.ultimaAttivita ?? .distantPast) }
    }
}
