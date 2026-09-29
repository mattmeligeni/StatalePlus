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
