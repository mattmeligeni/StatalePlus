import Foundation

nonisolated struct HTTPResponse: Sendable {
    let data: Data
    let url: URL          // URL finale dopo i redirect
    let status: Int
    let contentType: String
    let encoding: String.Encoding

    var text: String { String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self) }
    var isPDF: Bool { contentType.contains("pdf") || data.prefix(4) == Data("%PDF".utf8) }
}

nonisolated enum NetError: LocalizedError, Equatable {
    case noCredentials
    case invalidCredentials
    case sessionExpired
    case insecureURL
    case blockedLogoutURL
    case cloudflareChallenge
    case http(Int)
    case unexpectedPage(String)
    case cas(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials: "Nessuna credenziale salvata."
        case .invalidCredentials: "Email o password non corrette."
        case .sessionExpired: "Sessione scaduta e nuovo accesso non riuscito."
        case .insecureURL: "Collegamento non sicuro bloccato (solo HTTPS)."
        case .blockedLogoutURL: "Collegamento di logout bloccato per non chiudere la sessione universitaria."
        case .cloudflareChallenge: "Il sito universitario ha richiesto una verifica anti-bot. Riprova più tardi."
        case .http(let c): "Il server ha risposto con errore \(c)."
        case .unexpectedPage(let w): "Risposta inattesa da \(w)."
        case .cas(let messaggio): "Login di Ateneo: \(messaggio)"
        }
    }
}

nonisolated enum AppHTTP {
    /// UA unico e coerente per tutte le richieste: base Safari iOS + un token che identifica l'app.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 StatalePlus/1.0"

    /// Link che NON vanno mai seguiti: una `ClosingPage` Wicket fa Single Logout e invalida il CASTGC condiviso
    ///.
    static func isLogout(_ url: URL) -> Bool {
        url.absoluteString.range(of: #"(?i)(logout|logoff|checklogout|clearsession|dologout|closingpage|signout)"#,
                                 options: .regularExpression) != nil
    }

    static func formEncode(_ fields: [(String, String)]) -> Data {
        // Solo ASCII non riservato (come un browser con application/x-www-form-urlencoded): lettere accentate
        // e simboli vengono codificati in UTF-8 percent-encoding.
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._*")
        func enc(_ s: String) -> String {
            (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s).replacingOccurrences(of: "%20", with: "+")
        }
        return Data(fields.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&").utf8)
    }
}

/// Blocca redirect verso HTTP in chiaro o verso URL di logout (restituisce la risposta 3xx al chiamante).
/// Variante a completion handler di proposito: con Swift 6.4 la variante `async` fa andare in crash
/// swift-frontend (SILGen, emitNativeToForeignThunk) in una classe `nonisolated`.
nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", !AppHTTP.isLogout(url) else { return completionHandler(nil) }
        completionHandler(request)
    }
}

/// Client HTTP con rate limiting per host. Due profili:
/// - `.authenticated`: `HTTPCookieStorage.shared` (porta il CASTGC su *.unimi.it e il cookie `arielauth`);
/// - `.anonymous`: nessun cookie. Le API pubbliche stanno su `orari-be.divsi.unimi.it`, un sottodominio di
///   unimi.it: con lo store condiviso riceverebbero il `CASTGC` (dominio `.unimi.it`, vedi unimia_cookies.lwp).
actor HTTPClient {
    enum Profile { case authenticated, anonymous }

    private let session: URLSession
    private let guardDelegate = RedirectGuard()
    private let minInterval: Duration
    private var nextSlot: [String: ContinuousClock.Instant] = [:]

    init(profile: Profile, minInterval: Duration) {
        let cfg: URLSessionConfiguration
        switch profile {
        case .authenticated:
            cfg = .default
            cfg.httpCookieStorage = .shared
            cfg.httpShouldSetCookies = true
            cfg.httpCookieAcceptPolicy = .always
        case .anonymous:
            cfg = .ephemeral
            cfg.httpCookieStorage = nil
            cfg.httpShouldSetCookies = false
        }
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 30
        // 30 s senza dati bastano a considerare morta una richiesta; il tetto totale è alto per gli zip dei corsi.
        cfg.timeoutIntervalForResource = 900
        cfg.tlsMinimumSupportedProtocolVersion = .TLSv12
        cfg.httpAdditionalHeaders = [
            "User-Agent": AppHTTP.userAgent,
            "Accept-Language": "it-IT,it;q=0.9,en;q=0.8",
        ]
        session = URLSession(configuration: cfg, delegate: guardDelegate, delegateQueue: nil)
        self.minInterval = minInterval
    }

    func get(_ url: URL, headers: [String: String] = [:]) async throws -> HTTPResponse {
        var req = URLRequest(url: url)
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return try await send(req)
    }

    func postForm(_ url: URL, fields: [(String, String)], headers: [String: String] = [:]) async throws -> HTTPResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = AppHTTP.formEncode(fields)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return try await send(req)
    }

    func postJSON(_ url: URL, body: some Encodable & Sendable, headers: [String: String] = [:]) async throws -> HTTPResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONEncoder().encode(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return try await send(req)
    }

    /// POST di un form con risposta scritta su file (download grandi, niente dati in memoria). Il file restituito
    /// è in una cartella temporanea dell'app e va spostato dal chiamante.
    func downloadForm(_ url: URL, fields: [(String, String)]) async throws -> (URL, HTTPURLResponse) {
        guard url.scheme == "https" else { throw NetError.insecureURL }
        guard !AppHTTP.isLogout(url) else { throw NetError.blockedLogoutURL }
        await throttle(host: url.host() ?? "")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = AppHTTP.formEncode(fields)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600
        let (temp, response) = try await session.download(for: req, delegate: guardDelegate)
        guard let http = response as? HTTPURLResponse else { throw NetError.unexpectedPage(url.host() ?? "") }
        // Il file temporaneo di URLSession può sparire appena si torna: lo si sposta subito.
        let copia = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.moveItem(at: temp, to: copia)
        return (copia, http)
    }

    private func send(_ req: URLRequest) async throws -> HTTPResponse {
        guard let url = req.url, url.scheme == "https" else { throw NetError.insecureURL }
        guard !AppHTTP.isLogout(url) else { throw NetError.blockedLogoutURL }
        await throttle(host: url.host() ?? "")

        let (data, response) = try await session.data(for: req, delegate: guardDelegate)
        guard let http = response as? HTTPURLResponse else { throw NetError.unexpectedPage(url.host() ?? "") }
        let ct = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let encoding: String.Encoding = {
            guard let name = http.textEncodingName else { return .utf8 }
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            return cf == kCFStringEncodingInvalidId ? .utf8 : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }()
        let result = HTTPResponse(data: data, url: http.url ?? url, status: http.statusCode, contentType: ct, encoding: encoding)
        if Self.isCloudflareChallenge(http, result) { throw NetError.cloudflareChallenge }
        if (300..<400).contains(http.statusCode) { // redirect bloccato dal RedirectGuard
            let location = http.value(forHTTPHeaderField: "Location").flatMap { URL(string: $0, relativeTo: url) }
            throw location.map(AppHTTP.isLogout) == true ? NetError.blockedLogoutURL : NetError.insecureURL
        }
        if http.statusCode >= 500 { throw NetError.http(http.statusCode) }
        return result
    }

    /// Distanzia le richieste allo stesso host: il prossimo slot viene prenotato PRIMA di sospendersi,
    /// così anche le chiamate rientranti sull'attore restano distanziate.
    private func throttle(host: String) async {
        let clock = ContinuousClock()
        let now = clock.now
        let slot = max(now, nextSlot[host] ?? now)
        nextSlot[host] = slot + minInterval
        if slot > now { try? await clock.sleep(until: slot) }
    }

    /// Rileva una challenge Cloudflare.
    private static func isCloudflareChallenge(_ http: HTTPURLResponse, _ r: HTTPResponse) -> Bool {
        if http.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge" { return true }
        guard [403, 429, 503].contains(http.statusCode) || r.contentType.contains("html") else { return false }
        let head = String(decoding: r.data.prefix(4000), as: UTF8.self).lowercased()
        return head.contains("/cdn-cgi/challenge-platform") || head.contains("cf_chl_opt")
    }
}

nonisolated enum CookieJar {
    static func has(_ name: String) -> Bool {
        HTTPCookieStorage.shared.cookies?.contains { $0.name == name && $0.domain.hasSuffix("unimi.it") } ?? false
    }
    /// Logout locale: rimuove tutti i cookie universitari (CASTGC, arielauth, MoodleSession, JSESSIONID, __cf_bm…).
    static func clearUniversityCookies() {
        let store = HTTPCookieStorage.shared
        store.cookies?.filter { $0.domain.hasSuffix("unimi.it") }.forEach(store.deleteCookie)
    }
}
