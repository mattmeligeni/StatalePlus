import Foundation

/// Parsing delle app SIFA (Wicket) su studente.unimi.it.
nonisolated enum SifaParser {
    /// Vero se la risposta è una pagina d'app autenticata.
    static func isAuthenticated(html: String, finalURL: URL, app: SifaApp) -> Bool {
        let onCAS = finalURL.host() == "cas.unimi.it"
        let casError = html.contains("name=\"unicas-form\"") || html.contains("Accesso non riuscito")
        let inApp = finalURL.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasPrefix(app.root)
        return !onCAS && !casError && (inApp || html.contains("Logout") || html.contains("Matricola"))
    }

    /// Intestazione comune alle app Wicket: `<b>Matricola:</b> 12345A`.
    static func matricolaHeader(html: String) -> String? {
        html.firstMatch(#"<b>Matricola:</b>\s*([0-9A-Za-z]+)"#)
    }

    /// "Esami del tuo corso di studio": `table.smart-table` Codice | Descrizione | Crediti | [Iscrizione].
    static func esamiNonSostenuti(html: String) throws -> [EsameIscrivibile] {
        let doc = HTML.parse(html)
        guard let table = doc.first("table.smart-table") ?? doc.first("table") else { return [] }
        let heads = table.select("thead th").map(\.text)
        let iCod = heads.firstIndex(of: "Codice") ?? 0
        let iDesc = heads.firstIndex(of: "Descrizione") ?? 1
        let iCred = heads.firstIndex(of: "Crediti") ?? 2
        return table.select("tbody tr").compactMap { tr in
            let tds = tr.select("td")
            guard tds.count > max(iCod, iDesc, iCred) else { return nil }
            var codice = tds[iCod].text
            while codice.hasSuffix("-") { codice.removeLast() }
            return EsameIscrivibile(codice: codice.trimmed,
                                    descrizione: tds[iDesc].text,
                                    crediti: Int(tds[iCred].text) ?? 0,
                                    iscrizioneListenerPath: tr.first("a[href*=ILinkListener]")?.attr("href"))
        }
    }

    /// Prenotazioni confermate / esiti finali. `vuotoMarker` è il testo del caso vuoto.
    static func tabella(html: String, vuotoMarker: String) throws -> TabellaSifa {
        let doc = HTML.parse(html)
        let main = doc.first("[role=main]") ?? doc
        if main.text.range(of: vuotoMarker, options: .caseInsensitive) != nil {
            return TabellaSifa(vuota: true, messaggio: vuotoMarker, colonne: [], righe: [])
        }
        guard let table = main.first("table.smart-table") ?? main.first("table") else {
            return TabellaSifa(vuota: true, messaggio: nil, colonne: [], righe: [])
        }
        let heads = table.select("thead th").map(\.text)
        let righe: [[String: String]] = table.select("tbody tr").compactMap { tr in
            let cells = tr.select("td").map(\.text)
            guard !cells.isEmpty else { return nil }
            let keys = heads.count == cells.count ? heads : cells.indices.map { "Colonna \($0 + 1)" }
            return Dictionary(zip(keys, cells), uniquingKeysWith: { a, _ in a }).filter { !$0.key.isEmpty }
        }
        return TabellaSifa(vuota: righe.isEmpty, messaggio: nil, colonne: heads.filter { !$0.isEmpty }, righe: righe)
    }
}
