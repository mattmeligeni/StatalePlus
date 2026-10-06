import Foundation

/// Parsing delle API mobili Agenda Studenti (JSON + XML).
nonisolated enum AgendaParser {
    static func alberoCorsi(_ data: Data) throws -> [AgendaScuola] {
        try JSONDecoder().decode([AgendaScuola].self, from: data)
    }

    static func insegnamenti(_ data: Data) throws -> [InsegnamentoAgenda] {
        if data.isEmpty { return [] }
        return try JSONDecoder().decode([InsegnamentoAgenda].self, from: data)
    }

    static func appelli(_ data: Data) throws -> [Appello] {
        let resp = try JSONDecoder().decode(EsamiResponse.self, from: data)
        var out: [Appello] = []
        for (_, ins) in resp.insegnamenti.values {
            let docenti = (ins.docenti?.values ?? [:]).values
                .map { "\($0.nome.capitalized) \($0.cognome.capitalized)".trimmed }
                .sorted()
            for a in ins.appelli {
                guard let day = Formats.dayDMY(a.data) else { continue }
                let inizio = Formats.at(day, a.oraInizio)
                    ?? a.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    ?? day
                out.append(Appello(id: a.eventId.isEmpty ? "\(ins.dati.codice)-\(a.data)" : a.eventId,
                                   codiceInsegnamento: ins.dati.codice, insegnamento: ins.dati.nome,
                                   docenti: docenti, inizio: inizio, fine: Formats.at(day, a.oraFine),
                                   aula: a.aula, sede: a.sede, aulaCodici: a.aulaCodici,
                                   tipo: a.tipo, passato: a.passato, annullato: a.annullato, note: a.note))
            }
        }
        return out.sorted { $0.inizio < $1.inizio }
    }

    /// XML orario. Corpo vuoto → orario non pubblicato.
    static func orario(_ data: Data) throws -> OrarioInsegnamento {
        guard !data.isEmpty else { return OrarioInsegnamento(dataInizio: nil, dataFine: nil, festivita: [], lezioni: []) }
        let delegate = OrarioXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        return OrarioInsegnamento(dataInizio: delegate.dataInizio, dataFine: delegate.dataFine,
                                  festivita: delegate.festivita, lezioni: delegate.lezioni)
    }
}

/// Delegate SAX per `<Orario>` → `<Insegnamento>` → `<DocenteTitolare/>` + `<CalendarioLezioni><Giorno/>…`.
nonisolated private final class OrarioXMLDelegate: NSObject, XMLParserDelegate {
    var dataInizio: Date?
    var dataFine: Date?
    var festivita: [Date] = []
    var lezioni: [Lezione] = []

    private var insegnamento: [String: String] = [:]
    private var docente = ""
    private var giorni: [[String: String]] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "Orario":
            dataInizio = Formats.dayDMY(a["DataInizio"] ?? "")
            dataFine = Formats.dayDMY(a["DataFine"] ?? "")
        case "GiornoFestivita":
            if let d = Formats.dayISO(a["Giorno"] ?? "") { festivita.append(d) }
        case "Insegnamento":
            insegnamento = a; docente = ""; giorni = []
        case "DocenteTitolare":
            let full = "\(a["Nome"] ?? "") \(a["Cognome"] ?? "")".trimmed
            if docente.isEmpty { docente = full.capitalized }
        case "Giorno":
            giorni.append(a)
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "Insegnamento" else { return }
        for g in giorni {
            guard let day = Formats.dayDMY(g["Data"] ?? ""),
                  let inizio = Formats.at(day, g["OraInizio"] ?? ""),
                  let fine = Formats.at(day, g["OraFine"] ?? "") else { continue }
            let note = [g["Notes"], g["NoteAula"], g["NoteSettimanali"]].compactMap { $0?.trimmed }.filter { !$0.isEmpty }
            lezioni.append(Lezione(
                id: g["id"] ?? g["Codice"] ?? UUID().uuidString,
                codiceInsegnamento: insegnamento["CodiceGenerale"] ?? insegnamento["Codice"] ?? "",
                insegnamento: insegnamento["Nome"] ?? "",
                docente: docente,
                inizio: inizio, fine: fine,
                aula: g["Aula"] ?? "", aulaCodice: g["AulaCodice"] ?? "", sede: g["Sede"] ?? "",
                annullato: g["Annullato"] == "1",
                tipo: g["Tipo"] ?? "Lezione",
                note: note.joined(separator: "\n")))
        }
    }
}
