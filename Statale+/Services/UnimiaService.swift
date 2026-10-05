import Foundation

/// UNIMIA (Oracle WebCenter / Plumtree)
actor UnimiaService {
    private let cas: CASSession
    private static let portal = "https://unimia.unimi.it/portal/server.pt"
    private static let homeURL = URL(string: "\(portal)/community/unimia/207/home/8993")!

    init(cas: CASSession) { self.cas = cas }

    /// Home community (8993): profilo, recapiti, codice corso — fonte della matricola che sblocca tutto il resto.
    func profilo() async throws -> (Studente, Recapiti) {
        let r = try await cas.unimia(Self.homeURL)
        return try UnimiaParser.profilo(html: r.text)
    }

    /// Portlet async 219 (tasse/pagamenti), con Referer e X-Requested-With.
    func tasse() async throws -> SituazioneTasse {
        try UnimiaParser.tasse(html: try await asyncPortlet(219))
    }

    func esitiInAttesa() async throws -> EsitiInAttesa {
        try UnimiaParser.esitiInAttesa(html: try await asyncPortlet(240))
    }

    func iscrizioniAppelli() async throws -> StatoIscrizioniAppelli {
        try UnimiaParser.iscrizioniAppelli(html: try await asyncPortlet(310))
    }

    /// Gateway Plumtree del portlet Carriera (209). Convenzione: `:`→`%3B`, `//`→`/`, barre letterali,
    /// NIENTE quote totale del path.
    func libretto(matricola: String) async throws -> Libretto {
        let m = matricola.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? matricola
        let url = URL(string: "\(Self.portal)/gateway/PTARGS_0_0_209_207_0_43/"
            + "http%3B/portlets.alui.unimi.it%3B8880/portale_utenti_cocoon_portlet/carriera.html"
            + "?modalita=dettaglio&show_laureato=false&index=1&tipo=stu&matricola=\(m)&dottorato=")!
        let r = try await cas.unimia(url, headers: [
            "Referer": "\(Self.portal)/community/unimia/207/carriera/8997",
            "X-Requested-With": "XMLHttpRequest",
        ])
        return try UnimiaParser.libretto(html: r.text)
    }

    private func asyncPortlet(_ pid: Int) async throws -> String {
        let url = URL(string: "\(Self.portal)/gateway/PTARGS_6_0_\(pid)_207_8993_43/")!
        return try await cas.unimia(url, headers: [
            "Referer": Self.homeURL.absoluteString,
            "X-Requested-With": "XMLHttpRequest",
        ]).text
    }
}
