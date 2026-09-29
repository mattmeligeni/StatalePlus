import Foundation

/// Sessione Ariel/myAriel: login PROPRIO (form ASP.NET su elearning.unimi.it), NON ticket CAS.
actor ArielSession {
    static let home = URL(string: "https://ariel.unimi.it/")!
    static let loginPage = URL(string: "https://elearning.unimi.it/authentication/skin/portaleariel/login.aspx?url=https://ariel.unimi.it/")!
    static let moodle = "https://myariel.unimi.it"

    let http: HTTPClient
    private var cachedSesskey: String?
    private var inFlightLogin: Task<Void, Error>?

    init(http: HTTPClient) { self.http = http }

    func ensureLoggedIn(with credentials: Credentials? = nil) async throws {
        if let inFlightLogin { return try await inFlightLogin.value }
        let task = Task { try await self.login(credentials) }
        inFlightLogin = task
        defer { inFlightLogin = nil }
        try await task.value
    }

    private func login(_ given: Credentials?) async throws {
        let r = try await http.get(Self.home)
        if ArielParser.isAuthenticated(r.text) { return }

        var form = try ArielParser.loginForm(r.text, pageURL: r.url)
        if form == nil {
            let page = try await http.get(Self.loginPage)
            form = try ArielParser.loginForm(page.text, pageURL: page.url)
        }
        guard let form else { throw ArielError.loginFormNotFound }
        guard let creds = given ?? KeychainStore.load() else { throw NetError.noCredentials }

        // Tutti i campi del form (anche __VIEWSTATE…), con override come in ensure_ariel:
        // tbLogin = parte locale, ddlType = dominio, hdnSilent = true.
        let overrides = ["tbLogin": creds.localPart, "tbPassword": creds.password,
                         "ddlType": creds.domain, "hdnSilent": "true"]
        var fields = form.fields.map { ($0.0, overrides[$0.0] ?? $0.1) }
        for (k, v) in overrides where !fields.contains(where: { $0.0 == k }) { fields.append((k, v)) }

        let resp = try await http.postForm(form.action, fields: fields)
        guard ArielParser.isAuthenticated(resp.text) || CookieJar.has("arielauth") else { throw ArielError.invalidCredentials }
        cachedSesskey = nil
    }

    /// GET su Ariel/myAriel con re-login trasparente.
    func page(_ url: URL) async throws -> HTTPResponse {
        let r = try await http.get(url)
        guard looksLoggedOut(r) else { return r }
        try await ensureLoggedIn()
        cachedSesskey = nil
        return try await http.get(url)
    }

    private func looksLoggedOut(_ r: HTTPResponse) -> Bool {
        r.url.host() == "elearning.unimi.it" || r.url.path().hasPrefix("/login") || r.text.contains("name=\"tbPassword\"")
    }

    /// `sesskey` Moodle dalla config JS di una pagina autenticata.
    func sesskey() async throws -> String {
        if let cachedSesskey { return cachedSesskey }
        let r = try await page(URL(string: "\(Self.moodle)/my/")!)
        guard let key = ArielParser.sesskey(r.text) else { throw ArielError.noSesskey }
        cachedSesskey = key
        return key
    }

    /// AJAX `core_courseformat_get_state`.
    func courseState(courseId: String) async throws -> CourseState {
        struct Call: Encodable, Sendable {
            let index = 0
            let methodname = "core_courseformat_get_state"
            let args: Args
            struct Args: Encodable, Sendable { let courseid: Int }
        }
        guard let id = Int(courseId) else { throw ArielError.ajax("courseid non valido") }
        for attempt in 0..<2 {
            let key = try await sesskey()
            let url = URL(string: "\(Self.moodle)/lib/ajax/service.php?sesskey=\(key)&info=core_courseformat_get_state")!
            let r = try await http.postJSON(url, body: [Call(args: .init(courseid: id))])
            do {
                return try ArielParser.courseState(r.data)
            } catch ArielError.ajax(let code) where attempt == 0 && (code.contains("sesskey") || code.contains("login")) {
                cachedSesskey = nil
                try await ensureLoggedIn()
            }
        }
        throw ArielError.noSesskey
    }

    /// Scarica un file `pluginfile.php` in una cartella temporanea (solo per l'anteprima, poi eliminabile).
    func download(_ file: FileMoodle) async throws -> URL {
        guard file.url.host() == "myariel.unimi.it" else { throw NetError.insecureURL }
        let r = try await page(file.url)
        guard r.status == 200 else { throw NetError.http(r.status) }
        let dir = FileManager.default.temporaryDirectory.appending(path: "ariel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = r.url.lastPathComponent.removingPercentEncoding ?? file.nome
        let dest = dir.appending(path: name.isEmpty ? file.nome : name)
        try r.data.write(to: dest, options: [.atomic, .completeFileProtection])
        return dest
    }
}
