import Foundation

/// Parsing di Ariel (offerta, login ASP.NET) e myAriel (Moodle).
nonisolated enum ArielParser {
    // MARK: Sessione

    /// La home autenticata contiene "Logout".
    static func isAuthenticated(_ html: String) -> Bool { html.contains("Logout") }

    /// `"sesskey":"…"` nella config JS `M.cfg`.
    static func sesskey(_ html: String) -> String? { html.firstMatch(#""sesskey":"([^"]+)""#) }

    /// Form ASP.NET con `tbLogin`/`tbPassword`: tutti i campi (anche `__VIEWSTATE` & co.) e i default dei `<select>`.
    static func loginForm(_ html: String, pageURL: URL) throws -> (action: URL, fields: [(String, String)])? {
        let doc = HTML.parse(html)
        for form in doc.select("form") {
            let inputs = form.select("input, select")
            let names = Set(inputs.map { $0.attr("name") })
            guard names.contains("tbLogin"), names.contains("tbPassword") else { continue }
            var fields: [(String, String)] = []
            for el in inputs {
                let name = el.attr("name")
                guard !name.isEmpty else { continue }
                if el.tag == "select" {
                    let opt = el.first("option[selected]") ?? el.first("option")
                    fields.append((name, opt?.attr("value") ?? ""))
                } else {
                    fields.append((name, el.attr("value")))
                }
            }
            let actionAttr = form.attr("action")
            let action = actionAttr.isEmpty ? pageURL : (HTML.absoluteURL(actionAttr, base: pageURL) ?? pageURL)
            return (action, fields)
        }
        return nil
    }

    // MARK: Offerta

    static func offerta(_ html: String, annoAccademico: String) throws -> [InsegnamentoOfferta] {
        let doc = HTML.parse(html)
        var out: [InsegnamentoOfferta] = []
        // Solo le righe esterne: hanno `td.col-md-1 > span.tag`. Le righe annidate ("Edizione") no.
        for codeCell in doc.select("td.col-md-1") {
            guard let tag = codeCell.first("span.tag"), let row = codeCell.parentElement else { continue }
            let codice = tag.text
            let titolo = HTML.text(row.first("td.col-md-11 strong"))
            guard !codice.isEmpty, !titolo.isEmpty, titolo.lowercased() != "edizione" else { continue }

            var courseId: String?
            var titolari: [String] = []
            for tab in row.select("a.nav-link[href^=#sp-]") where HTML.text(tab.first("small")) == annoAccademico {
                guard let pane = doc.element(id: String(tab.attr("href").dropFirst())) else { continue }
                courseId = pane.first("a[href*=course/view.php?id=]")?.attr("href").firstMatch(#"course/view\.php\?id=(\d+)"#)
                titolari = pane.select("ul.list-user a").map(\.text).filter { !$0.isEmpty }
                break
            }
            if !out.contains(where: { $0.codice == codice }) {
                out.append(InsegnamentoOfferta(codice: codice, titolo: titolo, courseId: courseId,
                                               annoAccademico: annoAccademico, titolari: titolari))
            }
        }
        return out
    }

    // MARK: Struttura

    static func courseState(_ data: Data) throws -> CourseState {
        let envelopes = try JSONDecoder().decode([MoodleAjaxEnvelope].self, from: data)
        guard let first = envelopes.first else { throw ArielError.ajax("risposta vuota") }
        guard !first.error, let payload = first.data else {
            throw ArielError.ajax(first.exception?.errorcode ?? first.exception?.message ?? "errore AJAX")
        }
        return try JSONDecoder().decode(CourseState.self, from: Data(payload.utf8))
    }

    // MARK: Scheda

    static func scheda(_ html: String) throws -> SchedaInsegnamento? {
        let doc = HTML.parse(html)
        guard let block = doc.first("section.block_w4info") ?? doc.first(".block_w4info") else { return nil }
        var values: [String: HTMLNode] = [:]
        var docenti: [String] = []
        for tr in block.select("tr") {
            let tds = tr.elementChildren.filter { $0.tag == "td" }
            guard tds.count >= 2, let h6 = tds[0].first("h6") else { continue }
            let label = h6.text.trimmingCharacters(in: CharacterSet(charactersIn: ": ")).trimmed
            guard !label.isEmpty else { continue }
            if label == "Docente" { docenti.append(tds[1].text) }
            if values[label] == nil { values[label] = tds[1] }
        }
        func text(_ k: String) -> String? { values[k].map(\.text).flatMap { $0.isEmpty ? nil : $0 } }
        func link(_ k: String) -> URL? { values[k]?.first("a[href]").flatMap { URL(string: $0.attr("href")) } }
        let mail = block.first("a[href^=mailto:]").map { String($0.attr("href").dropFirst("mailto:".count)) }
        let cv = block.first("a[href*=/cv/]").flatMap { URL(string: $0.attr("href")) }
        let calendario = link("Calendario lezioni")
        // "…&anno=2026&attivita%5b%5d=ECDBD-29_1": codice Agenda dell'insegnamento, prefisso "EC" rimosso.
        let decoded = calendario?.absoluteString.removingPercentEncoding ?? ""
        var codiceAgenda = decoded.firstMatch(#"attivita\[\]=([A-Za-z0-9_\-]+)"#)
        if let c = codiceAgenda, c.hasPrefix("EC") { codiceAgenda = String(c.dropFirst(2)) }
        return SchedaInsegnamento(annoAccademico: text("Anno accademico"), obiettivi: text("Obiettivi formativi"),
                                  periodo: text("Periodo"), lingua: text("Lingua"), docenti: docenti,
                                  programmaURL: link("Insegnamento"), calendarioURL: calendario,
                                  emailDocente: mail, cvDocenteURL: cv,
                                  codiceAgenda: codiceAgenda,
                                  annoAgenda: decoded.firstMatch(#"anno=(\d{4})"#))
    }

    // MARK: Moduli

    static func modulo(_ html: String) throws -> ModuloDettaglio {
        let doc = HTML.parse(html)
        let base = URL(string: "https://myariel.unimi.it/")!
        let intro = doc.element(id: "intro") ?? doc.first(".activity-description")
        var files: [FileMoodle] = []
        for a in doc.select("[role=main] a[href*=/pluginfile.php/], #region-main a[href*=/pluginfile.php/]") {
            guard let url = HTML.absoluteURL(a.attr("href"), base: base), !files.contains(where: { $0.url == url }) else { continue }
            let name = a.text
            files.append(FileMoodle(nome: name.isEmpty ? url.lastPathComponent.removingPercentEncoding ?? "file" : name, url: url))
        }
        return ModuloDettaglio(descrizione: HTML.readableText(intro), file: files, discussioni: discussioni(doc))
    }

    private static func discussioni(_ doc: HTMLNode) -> [DiscussioneForum] {
        doc.select("tr[data-region=discussion-list-item]").compactMap { tr in
            let id = tr.attr("data-discussionid")
            guard !id.isEmpty, let a = tr.first("th.topic a[href*=discuss.php]"), let url = URL(string: a.attr("href")) else { return nil }
            func ts(_ sel: String) -> Date? {
                tr.first(sel).flatMap { TimeInterval($0.attr("data-timestamp")) }.map { Date(timeIntervalSince1970: $0) }
            }
            return DiscussioneForum(id: id, titolo: a.text,
                                    autore: HTML.text(tr.first("td.author .author-info > div")),
                                    creata: ts("time[id^=time-created]"), ultimaAttivita: ts("time[id^=time-modified]"),
                                    url: url)
        }
    }

    static func posts(_ html: String) throws -> [PostForum] {
        HTML.parse(html).select("[data-region=post]").map { p in
            PostForum(id: p.attr("data-post-id"),
                      oggetto: HTML.text(p.first("[data-region-content=forum-post-core-subject]")),
                      autore: HTML.text(p.first("header a[href*=/user/view.php]")),
                      data: p.first("time[datetime]").flatMap { Formats.isoDate($0.attr("datetime")) },
                      testo: HTML.readableText(p.first(".post-content-container")))
        }
    }

    // MARK: Partecipanti / valutazioni

    static func partecipanti(_ html: String) throws -> [Partecipante] {
        guard let table = HTML.parse(html).element(id: "participants") else { return [] }
        return table.select("tbody tr").compactMap { tr in
            guard let a = tr.first("a[href*=/user/view.php?id=]"), let uid = a.attr("href").firstMatch(#"id=(\d+)"#) else { return nil }
            let title = a.first("span.userinitials")?.attr("title") ?? ""
            let nome = title.isEmpty ? a.ownText : title
            let cells = tr.elementChildren
            return Partecipante(id: uid, nome: nome,
                                ruoli: cells.count > 2 ? cells[2].text : "",
                                gruppi: cells.count > 3 ? cells[3].text : "")
        }
    }

    static func valutazioni(_ html: String) throws -> [VoceValutazione] {
        guard let table = HTML.parse(html).first("table.user-grade") else { return [] }
        return table.select("tbody tr").compactMap { tr in
            guard tr.first("td.column-grade") != nil else { return nil } // riga di categoria
            func col(_ c: String) -> String { HTML.text(tr.first(".column-\(c)")) }
            return VoceValutazione(elemento: col("itemname"), peso: col("weight"), valutazione: col("grade"),
                                   intervallo: col("range"), percentuale: col("percentage"), feedback: col("feedback"))
        }
    }
}

nonisolated enum ArielError: LocalizedError {
    case loginFormNotFound, invalidCredentials, noSesskey, ajax(String)
    var errorDescription: String? {
        switch self {
        case .loginFormNotFound: "Form di login Ariel non trovato."
        case .invalidCredentials: "Accesso ad Ariel non riuscito: controlla le credenziali."
        case .noSesskey: "Sessione Moodle non disponibile."
        case .ajax(let m): "Errore Moodle: \(m)"
        }
    }
}
