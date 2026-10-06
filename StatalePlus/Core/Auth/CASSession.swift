import Foundation
import OSLog

/// Sessione CAS condivisa da UNIMIA e SIFA.
actor CASSession {
    static let service = "https://unimia.unimi.it/portal/server.pt"
    static let loginURL: URL = {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let encoded = service.addingPercentEncoding(withAllowedCharacters: allowed)!
        return URL(string: "https://cas.unimi.it/login?service=\(encoded)")!
    }()

    let http: HTTPClient
    private var studenteWarm = false
    private var inFlightLogin: Task<Void, Error>?

    init(http: HTTPClient) { self.http = http }

    // MARK: Login

    /// Garantisce un CASTGC valido. Login concorrenti vengono unificati in un'unica richiesta.
    func ensureLoggedIn(with credentials: Credentials? = nil) async throws {
        if Demo.attiva { return }
        if let inFlightLogin { return try await inFlightLogin.value }
        let task = Task { try await self.probeAndLogin(credentials) }
        inFlightLogin = task
        defer { inFlightLogin = nil }
        try await task.value
    }

    private func probeAndLogin(_ given: Credentials?) async throws {
        // Se CAS rimbalza dritto sul portale, il CASTGC è ancora valido.
        let probe = try await http.get(Self.loginURL)
        if probe.url.host() == "unimia.unimi.it" { return }

        let doc = HTML.parse(probe.text)
        func value(_ name: String) -> String? { doc.first("input[name=\(name)]")?.attr("value") }
        guard let lt = value("lt"), let execution = value("execution") else {
            throw NetError.unexpectedPage("cas.unimi.it")
        }
        guard let creds = given ?? KeychainStore.load() else { throw NetError.noCredentials }

        // Campi e header del form CAS.
        let fields: [(String, String)] = [
            ("username", creds.email), ("password", creds.password), ("selTipoUtente", "S"),
            ("lt", lt), ("execution", execution), ("_eventId", "submit"),
            ("service", value("service") ?? Self.service),
            ("_responsive", "responsive"), ("hCancelLoginLink", ""), ("hForgotPasswordLink", ""),
        ]
        // Il 302 con ?ticket=ST-… viene seguito da URLSession (ticket monouso consumato).
        let r = try await http.postForm(URL(string: "https://cas.unimi.it/login")!, fields: fields, headers: [
            "Origin": "https://cas.unimi.it", "Referer": Self.loginURL.absoluteString, "Cache-Control": "no-cache",
        ])
        if r.url.host() == "cas.unimi.it" {
            let esito = Self.esitoPagina(r.text)
            Self.log.error("CAS: login non completato. Titolo: \(esito.titolo, privacy: .public) · messaggio: \(esito.messaggio ?? "nessuno", privacy: .public) · form: \(esito.form, privacy: .public)")
            if let m = esito.messaggio { throw NetError.cas(m) }
            if esito.form { throw NetError.invalidCredentials }
            throw NetError.cas("richiesto un passaggio aggiuntivo (\(esito.titolo)). Completa l'accesso una volta dal sito cas.unimi.it.")
        }
        studenteWarm = false
    }

    // MARK: Diagnostica

    static let log = Logger(subsystem: "com.mattiameligeni.StatalePlus", category: "login")

    /// Cosa mostra CAS dopo un POST non riuscito: messaggi d'errore visibili (`.alert-danger` non nascosti,
    /// `#msg`, `.errors`), presenza del form e titolo. Mai la password.
    static func esitoPagina(_ html: String) -> (messaggio: String?, form: Bool, titolo: String) {
        let doc = HTML.parse(html)
        let visibili = doc.select(".alert-danger, #msg, .errors, .error, .alert-warning")
            .filter { !$0.classes.contains("hidden") }
            .map(\.text)
            .filter { !$0.isEmpty }
        let titolo = HTML.text(doc.first("title"))
        return (visibili.first, UnimiaParser.isCASLoginForm(html), titolo.isEmpty ? "senza titolo" : titolo)
    }

    // MARK: UNIMIA

    /// GET su UNIMIA con re-login trasparente se la sessione è scaduta.
    func unimia(_ url: URL, headers: [String: String] = [:]) async throws -> HTTPResponse {
        let r = try await http.get(url, headers: headers)
        guard needsLogin(r) else { return r }
        try await ensureLoggedIn()
        let retry = try await http.get(url, headers: headers)
        if needsLogin(retry) { throw NetError.sessionExpired }
        return retry
    }

    private func needsLogin(_ r: HTTPResponse) -> Bool {
        r.url.host() == "cas.unimi.it" || UnimiaParser.isCASLoginForm(r.text)
    }

    // MARK: SIFA (studente.unimi.it)

    /// `studente.unimi.it` è dietro Cloudflare: a freddo `authorize` risponde 401. Un GET preliminare
    /// alla home ottiene `__cf_bm`.
    private func warmupStudente() async {
        guard !studenteWarm else { return }
        _ = try? await http.get(URL(string: "https://studente.unimi.it/")!)
        studenteWarm = true
    }

    /// Ingresso in un'app SIFA via `checkLogin.asp` (catena CAS `authorize` silenziosa).
    @discardableResult
    func enterSifa(_ app: SifaApp) async throws -> HTTPResponse {
        await warmupStudente()
        if let r = try? await http.get(app.checkLogin),
           SifaParser.isAuthenticated(html: r.text, finalURL: r.url, app: app) {
            return r
        }
        try await ensureLoggedIn()
        studenteWarm = false
        await warmupStudente()
        let r = try await http.get(app.checkLogin)
        guard SifaParser.isAuthenticated(html: r.text, finalURL: r.url, app: app) else { throw NetError.sessionExpired }
        return r
    }

    /// Pagina SIFA "montata a classe" (URL stabile, NON un `?N` Wicket effimero).
    func sifaPage(_ app: SifaApp, path: String) async throws -> HTTPResponse {
        try await enterSifa(app)
        let url = URL(string: "https://studente.unimi.it/\(app.root)/\(path)")!
        let r = try await http.get(url)
        guard SifaParser.isAuthenticated(html: r.text, finalURL: r.url, app: app) else { throw NetError.sessionExpired }
        return r
    }

    /// Segue un link Wicket (`?N-…ILinkListener…`) di una pagina appena caricata, nella stessa sessione:
    /// niente nuovo ingresso da `checkLogin`, che creerebbe una sessione diversa.
    func sifaFollow(_ app: SifaApp, url: URL) async throws -> HTTPResponse {
        guard url.host() == "studente.unimi.it", url.path().hasPrefix("/\(app.root)/") else { throw NetError.insecureURL }
        let r = try await http.get(url)
        guard SifaParser.isAuthenticated(html: r.text, finalURL: r.url, app: app) else { throw NetError.sessionExpired }
        return r
    }
}
