import Foundation

/// PDF pubblici dell'Ateneo (curriculum dei docenti su work.unimi.it, manifesti degli studi su apps.unimi.it),
/// scaricati senza cookie e mostrati nell'app con Quick Look invece di aprire il browser.
actor DocumentiPubblici {
    private let http: HTTPClient
    init(http: HTTPClient) { self.http = http }

    enum Errore: LocalizedError {
        case nonConsentito, nonPDF
        var errorDescription: String? {
            switch self {
            case .nonConsentito: "Documento non disponibile nell'app."
            case .nonPDF: "Il documento non è disponibile in questo momento."
            }
        }
    }

    func pdf(_ url: URL) async throws -> URL {
        guard url.scheme == "https", let host = url.host(), host.hasSuffix("unimi.it") else { throw Errore.nonConsentito }
        let r = try await http.get(url, headers: ["Accept": "application/pdf"])
        guard r.status == 200, r.isPDF else { throw Errore.nonPDF }
        let dir = FileManager.default.temporaryDirectory.appending(path: "documenti", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appending(path: url.lastPathComponent.isEmpty ? "documento.pdf" : url.lastPathComponent)
        try r.data.write(to: dest, options: .atomic)
        return dest
    }
}
