import Foundation

/// Parsing delle pagine UNIMIA (home community, portlet asincroni 212/219/240/310, gateway 209).
nonisolated enum UnimiaParser {
    enum Failure: Error { case missingBlock(String), missingField(String) }

    /// Home (o portlet 212): profilo + recapiti.
    static func profilo(html: String) throws -> (Studente, Recapiti) {
        let doc = HTML.parse(html)
        guard let studenteDiv = doc.element(id: "div_studente") else { throw Failure.missingBlock("div_studente") }
        let s = HTML.labelPairs(in: studenteDiv)
        let r = HTML.labelPairs(in: doc.element(id: "div_anagrafica"))

        guard let matricola = s["Matricola"], !matricola.isEmpty else { throw Failure.missingField("Matricola") }
        let corsoRaw = s["Corso"] ?? ""
        // "Neuropsicologia … (classe lm-51 r) (codice: DBD, classe: LM-51 R - Psicologia)"
        let codice = corsoRaw.firstMatch(#"codice:\s*([A-Za-z0-9]+)"#) ?? doc.text.firstMatch(#"codice:\s*([A-Za-z0-9]+)"#) ?? ""
        let corso = corsoRaw.components(separatedBy: "(codice:").first?.trimmed ?? corsoRaw

        // <h2> Home: NOME COGNOME </h2>
        let nome = doc.select("h2").map(\.text)
            .first { $0.hasPrefix("Home:") }
            .map { String($0.dropFirst("Home:".count)).trimmed } ?? ""

        let studente = Studente(
            nome: nome,
            matricola: matricola,
            tipoCorso: s["Tipo di corso"] ?? "",
            corso: corso,
            codiceCorso: codice,
            anno: Int(s["Anno"] ?? "") ?? 1,
            statoIscrizione: s["Tipo di iscrizione"] ?? "",
            ultimoAnnoIscrizione: s["Ultimo anno di iscrizione"] ?? "",
            email: r["Email"] ?? ""
        )
        let recapiti = Recapiti(residenza: r["Residenza"] ?? "", recapito: r["Recapito"] ?? "",
                                cellulare: r["Cellulare"] ?? "", email: r["Email"] ?? "")
        return (studente, recapiti)
    }

    /// Portlet 219 (o il blocco inline della home).
    static func tasse(html: String) throws -> SituazioneTasse {
        let doc = HTML.parse(html)
        guard let root = doc.element(id: "div_situazione_amministrativa") ?? doc.element(id: "lista-tasse") else {
            throw Failure.missingBlock("div_situazione_amministrativa")
        }
        let aa = HTML.text(root.first("#lista-tasse h4")).replacingOccurrences(of: "Anno accademico:", with: "").collapsed

        var righe: [RigaTassa] = []
        if let table = root.first("table") {
            let heads = table.select("thead th").map(\.text)
            for tr in table.select("tbody tr") {
                let cells = tr.select("td").map(\.text)
                guard cells.count == heads.count else { continue }
                let row = Dictionary(zip(heads, cells), uniquingKeysWith: { a, _ in a })
                righe.append(RigaTassa(
                    causale: row["Causale tasse"]?.trimmed ?? "",
                    rata: row["Rata"]?.trimmed ?? "",
                    dovuto: Formats.euro(row["Importo dovuto"] ?? "") ?? 0,
                    pagato: Formats.euro(row["Importo pagato"] ?? "") ?? 0,
                    dataPagamento: Formats.dayDMY(row["Data pagamento"] ?? ""),
                    daPagare: Formats.euro(row["Importo da pagare"] ?? "") ?? 0
                ))
            }
        }
        let messaggi = doc.select("#lista-messaggi li").map(\.text).filter { !$0.isEmpty }
        let prev = HTML.text(doc.element(id: "div_anni_precedenti"))
            .replacingOccurrences(of: "Anni accademici precedenti", with: "").trimmed
        return SituazioneTasse(annoAccademico: aa, righe: righe, messaggi: messaggi,
                               anniPrecedenti: prev.isEmpty ? nil : prev)
    }

    /// Gateway 209 (carriera/libretto).
    static func libretto(html: String) throws -> Libretto {
        let doc = HTML.parse(html)
        guard let cont = doc.element(id: "div_esami_studente") else { throw Failure.missingBlock("div_esami_studente") }
        let intest = HTML.text(cont.first("> div")).components(separatedBy: "Se hai bisogno").first?.trimmed ?? ""
        if cont.text.range(of: "non hai sostenuto alcun esame", options: .caseInsensitive) != nil {
            return Libretto(intestazione: intest, vuoto: true, colonne: [], righe: [])
        }
        var colonne: [String] = []
        var righe: [[String: String]] = []
        for table in cont.select("table") {
            let heads = table.select("th").map(\.text)
            if colonne.isEmpty { colonne = heads }
            for tr in table.select("tr") {
                let cells = tr.select("td").map(\.text)
                guard !cells.isEmpty else { continue }
                let keys = heads.count == cells.count ? heads : cells.indices.map { "Colonna \($0 + 1)" }
                righe.append(Dictionary(zip(keys, cells), uniquingKeysWith: { a, _ in a }))
            }
        }
        return Libretto(intestazione: intest, vuoto: righe.isEmpty, colonne: colonne, righe: righe)
    }

    /// Portlet 240.
    static func esitiInAttesa(html: String) throws -> EsitiInAttesa {
        let doc = HTML.parse(html)
        let root = doc.element(id: "div_verbali_web") ?? doc
        let nessuno = root.text.range(of: "non hai esiti d'esame in attesa", options: .caseInsensitive) != nil
        let msg = root.select("> div").map(\.text).last { !$0.isEmpty } ?? ""
        return EsitiInAttesa(inAttesa: !nessuno, messaggio: msg)
    }

    /// Portlet 310.
    static func iscrizioniAppelli(html: String) throws -> StatoIscrizioniAppelli {
        let nessuna = HTML.parse(html).text.range(of: "non risultano iscrizioni attive", options: .caseInsensitive) != nil
        return StatoIscrizioniAppelli(iscrizioniAttive: !nessuna,
                                      messaggio: nessuna ? "Non risultano iscrizioni attive." : "Hai iscrizioni attive agli appelli.")
    }

    /// Vero se la pagina è il form di login CAS (sessione scaduta): campi `lt`/`execution`.
    static func isCASLoginForm(_ html: String) -> Bool {
        html.contains("name=\"execution\"") && html.contains("name=\"lt\"")
    }
}
