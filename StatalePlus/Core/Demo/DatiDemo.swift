import Foundation
import UIKit

/// Dati della versione dimostrativa. Persone, corso e codici sono inventati (nessun dato reale); sedi e indirizzi
/// sono quelli pubblici dell'Ateneo. Le date si calcolano dalla settimana corrente, quindi la demo ha sempre
/// lezioni, presenze, avvisi e scadenze plausibili.
nonisolated enum DatiDemo {
    // MARK: Studente e corso

    static let codiceCorso = "NCN"
    static let nomeCorso = "Neuroscienze cognitive e neuropsicologia (classe lm-51)"
    static let cdlOrario = "9001"

    static let studente = Studente(
        nome: "MARIO ROSSI", matricola: "12345A", tipoCorso: "Corso di Laurea Magistrale",
        corso: nomeCorso, codiceCorso: codiceCorso, anno: 2, statoIscrizione: "IN CORSO",
        ultimoAnnoIscrizione: annoAccademico.replacingOccurrences(of: "/", with: " - 20"),
        email: "mario.rossi@studenti.unimi.it")

    static let recapiti = Recapiti(
        residenza: "via mario rossi 10 20100 milano MI italia", recapito: "via mario rossi 10 20100 milano MI italia",
        cellulare: "+39 333 000 0000", email: "mario.rossi@studenti.unimi.it")

    /// "2026/27"
    static var annoAccademico: String { Formats.currentAcademicYear() }
    static var annoInizio: Int { Int(annoAccademico.prefix(4)) ?? Formats.calendar.component(.year, from: .now) }

    struct Corso {
        let codice: String        // "NCN-12_1"
        let nome: String
        let docente: String
        let cfu: Int
        let orari: [(giorno: Int, dalle: String, alle: String)]   // giorno: 2 = lunedì
        let aula: Int             // indice in `aule`
        let courseId: String
        let primoSemestre: Bool
        var generale: String { String(codice.split(separator: "_").first ?? Substring(codice)) }
        var sigla: String { codice.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_1", with: "") }
    }

    static let corsi: [Corso] = [
        Corso(codice: "NCN-12_1", nome: "Neuropsicologia delle funzioni esecutive", docente: "Laura Bianchi", cfu: 6,
              orari: [(2, "09:30", "12:30"), (4, "14:30", "17:30")], aula: 0, courseId: "90012", primoSemestre: true),
        Corso(codice: "NCN-14_1", nome: "Neuroanatomia funzionale", docente: "Paolo Ferri", cfu: 6,
              orari: [(3, "08:30", "11:30"), (5, "08:30", "10:30")], aula: 4, courseId: "90014", primoSemestre: true),
        Corso(codice: "NCN-15_1", nome: "Psicofarmacologia clinica", docente: "Giulia Conti", cfu: 6,
              orari: [(3, "14:30", "17:30")], aula: 1, courseId: "90015", primoSemestre: true),
        Corso(codice: "NCN-17_1", nome: "Metodi di ricerca in neuroscienze cognitive", docente: "Marco Galli", cfu: 9,
              orari: [(5, "13:30", "16:30"), (6, "09:30", "12:30")], aula: 5, courseId: "90017", primoSemestre: true),
        Corso(codice: "NCN-19_1", nome: "Colloquio clinico in neuropsicologia", docente: "Anna Moretti", cfu: 6,
              orari: [(2, "14:30", "17:30")], aula: 2, courseId: "90019", primoSemestre: true),
        Corso(codice: "NCN-21_1", nome: "Riabilitazione neuropsicologica", docente: "Davide Ricci", cfu: 6,
              orari: [(4, "09:30", "12:30")], aula: 0, courseId: "90021", primoSemestre: false),
    ]

    static func corso(codice: String) -> Corso? { corsi.first { $0.codice == codice || $0.generale == codice } }
    static func corso(courseId: String) -> Corso? { corsi.first { $0.courseId == courseId } }

    // MARK: Sedi e aule (indirizzi pubblici dell'Ateneo)

    struct AulaDemo { let id: String; let nome: String; let codice: String; let capienza: Int; let sede: String; let indirizzo: String }

    static let aule: [AulaDemo] = [
        AulaDemo(id: "501", nome: "Aula 208", codice: "9001#208", capienza: 120, sede: "Settore didattico Mangiagalli", indirizzo: "via Luigi Mangiagalli, 31, Milano, 20133"),
        AulaDemo(id: "502", nome: "Aula 101", codice: "9001#101", capienza: 90, sede: "Settore didattico Mangiagalli", indirizzo: "via Luigi Mangiagalli, 31, Milano, 20133"),
        AulaDemo(id: "503", nome: "Aula Crociera Alta", codice: "9002#CRA", capienza: 200, sede: "Festa del Perdono", indirizzo: "via Festa del Perdono, 7, Milano, 20122"),
        AulaDemo(id: "504", nome: "Sala Napoleonica", codice: "9002#NAP", capienza: 150, sede: "Festa del Perdono", indirizzo: "via Sant'Antonio, 12, Milano, 20122"),
        AulaDemo(id: "505", nome: "Aula G24", codice: "9003#G24", capienza: 160, sede: "Città Studi - Celoria", indirizzo: "via Celoria, 20, Milano, 20133"),
        AulaDemo(id: "506", nome: "Aula Magna", codice: "9003#MAG", capienza: 300, sede: "Città Studi - Celoria", indirizzo: "via Celoria, 20, Milano, 20133"),
    ]

    // MARK: Agenda

    static func alberoOrario() -> [AgendaScuola] { albero(orario: true) }
    static func alberoEsami() -> [AgendaScuola] { albero(orario: false) }

    private static func albero(orario: Bool) -> [AgendaScuola] {
        let periodi = orario
            ? #"[{"label":"primo semestre","valore":"1-semestre","id":"9101"},{"label":"secondo semestre","valore":"2-semestre","id":"9102"}]"#
            : #"[{"label":"1 anno","valore":"1","id":"1"},{"label":"2 anno","valore":"2","id":"2"}]"#
        let cdl = orario
            ? #"{"label":"NEUROSCIENZE COGNITIVE E NEUROPSICOLOGIA (Classe LM-51)","valore":"\#(cdlOrario)","code":"\#(codiceCorso)","pub_periodi":\#(periodi),"codice_facolta":"psico"}"#
            : #"{"label":"NEUROSCIENZE COGNITIVE E NEUROPSICOLOGIA (Classe LM-51)","valore":"\#(codiceCorso)","pub_periodi":\#(periodi),"codice_facolta":"psico"}"#
        let json = #"[{"label":"Psicologia","valore":"psico","elenco_lauree":[{"tipo":"CDS MAGISTRALE","elenco_cdl":[\#(cdl)]}]}]"#
        return (try? JSONDecoder().decode([AgendaScuola].self, from: Data(json.utf8))) ?? []
    }

    static func insegnamenti(periodo: String) -> [InsegnamentoAgenda] {
        let primo = periodo == "9101"
        return corsi.filter { $0.primoSemestre == primo }.map { c in
            InsegnamentoAgenda(nome: c.nome, codice: c.codice, docente: c.docente.split(separator: " ").reversed().joined(separator: " "),
                               id: c.courseId + "_1", anno: "2", codiceFacolta: "psico",
                               file: "demo/\(c.codice)_\(primo ? 1 : 2)-semestre.xml", codiceCdl: codiceCorso,
                               crediti: String(c.cfu), terzaRiga: "Unico", erogante: "")
        }
    }

    /// Lezioni settimanali da sei settimane fa a otto settimane da oggi, più una lezione in corso adesso
    /// (in orario di lezione) per provare presenze e registrazione.
    static func lezioni(file: String) -> [Lezione] {
        guard let c = corsi.first(where: { file.contains($0.codice) }), c.primoSemestre else { return [] }
        let cal = Formats.calendar
        let lunedi = Formats.inizioSettimana(.now)
        var out: [Lezione] = []
        for settimana in -6...8 {
            guard let inizioSettimana = cal.date(byAdding: .weekOfYear, value: settimana, to: lunedi) else { continue }
            for o in c.orari {
                guard let giorno = cal.date(byAdding: .day, value: o.giorno - 2, to: inizioSettimana),
                      let inizio = Formats.at(giorno, o.dalle), let fine = Formats.at(giorno, o.alle) else { continue }
                out.append(lezione(c, inizio: inizio, fine: fine, annullata: settimana == 1 && o.giorno == c.orari.last?.giorno && c.codice == "NCN-15_1"))
            }
        }
        // Lezione in corso: solo per il primo corso, solo nella fascia delle lezioni e se non ce n'è già una.
        let ora = cal.component(.hour, from: .now)
        if c.codice == corsi[3].codice, (8..<18).contains(ora), !tutteLeLezioniDiOggi().contains(where: { $0.inizio <= .now && $0.fine > .now }) {
            let mezzora = cal.date(bySetting: .minute, value: cal.component(.minute, from: .now) < 30 ? 0 : 30, of: .now) ?? .now
            let inizio = cal.date(byAdding: .hour, value: -1, to: mezzora) ?? .now
            out.append(lezione(c, inizio: inizio, fine: inizio.addingTimeInterval(3 * 3600), annullata: false, id: "demo-ora"))
        }
        return out
    }

    private static func tutteLeLezioniDiOggi() -> [Lezione] {
        corsi.filter { $0.codice != corsi[3].codice && $0.primoSemestre }
            .flatMap { lezioni(file: "\($0.codice)_1-semestre.xml") }
            .filter { Formats.calendar.isDateInToday($0.inizio) }
    }

    private static func lezione(_ c: Corso, inizio: Date, fine: Date, annullata: Bool, id: String? = nil) -> Lezione {
        let a = aule[c.aula]
        let giorno = Formats.dmyString(inizio)
        return Lezione(id: id ?? "demo-\(c.codice)-\(giorno)-\(Formats.time(inizio))", codiceInsegnamento: c.generale,
                       insegnamento: c.nome, docente: c.docente, inizio: inizio, fine: fine, aula: a.nome,
                       aulaCodice: a.codice.replacingOccurrences(of: "#", with: "-"), sede: a.sede, annullato: annullata,
                       tipo: "Lezione", note: annullata ? "Lezione annullata per impegni istituzionali del docente." : "")
    }

    static func appelli() -> [Appello] {
        let cal = Formats.calendar
        var out: [Appello] = []
        for (i, c) in corsi.enumerated() {
            for (j, mesi) in [-1, 2, 4].enumerated() {
                guard let base = cal.date(byAdding: .month, value: mesi, to: Formats.inizioSettimana(.now)),
                      let giorno = cal.date(byAdding: .day, value: (i % 5), to: base),
                      let inizio = Formats.at(giorno, ["09:30", "14:00", "10:00"][j]) else { continue }
                let a = aule[(c.aula + j) % aule.count]
                out.append(Appello(id: "demo-app-\(c.codice)-\(j)", codiceInsegnamento: c.codice, insegnamento: c.nome,
                                   docenti: [c.docente], inizio: inizio, fine: inizio.addingTimeInterval(3 * 3600),
                                   aula: a.nome, sede: a.sede, aulaCodici: [a.codice], tipo: j == 0 ? "Esame" : "Esame scritto",
                                   passato: inizio < .now, annullato: false,
                                   note: j == 1 ? "Iscrizione obbligatoria su SIFA entro 5 giorni dalla data dell'appello." : ""))
            }
        }
        return out.sorted { $0.inizio < $1.inizio }
    }

    // MARK: EasyRoom

    static func occupazioneOggi() -> OccupazioneAule {
        let sedi = Dictionary(grouping: aule, by: \.sede).map { nome, aule in
            Sede(nome: nome, indirizzo: aule[0].indirizzo,
                 aule: aule.map { Aula(id: $0.id, nome: $0.nome, codice: $0.codice, capienza: $0.capienza, sede: $0.sede, indirizzo: $0.indirizzo) })
        }.sorted { $0.nome < $1.nome }
        var occupazioni: [Occupazione] = []
        for c in corsi where c.primoSemestre {
            for l in lezioni(file: "\(c.codice)_1-semestre.xml") where Formats.calendar.isDateInToday(l.inizio) && !l.annullato {
                occupazioni.append(Occupazione(id: "occ-\(l.id)", dalle: oraSQL(l.inizio), alle: oraSQL(l.fine), aulaId: aule[c.aula].id,
                                               nome: c.nome, docente: c.docente, tipo: "Lezione"))
            }
        }
        occupazioni += [
            Occupazione(id: "occ-x1", dalle: "08:30:00", alle: "10:30:00", aulaId: "503", nome: "Storia moderna", docente: "Elena Marini", tipo: "Lezione"),
            Occupazione(id: "occ-x2", dalle: "11:00:00", alle: "13:00:00", aulaId: "506", nome: "Fisiologia generale", docente: "Luca Fontana", tipo: "Lezione"),
            Occupazione(id: "occ-x3", dalle: "14:00:00", alle: "18:00:00", aulaId: "504", nome: "Seminario di dipartimento", docente: "", tipo: "Evento"),
            Occupazione(id: "occ-x4", dalle: "09:00:00", alle: "12:00:00", aulaId: "502", nome: "Diritto privato", docente: "Sara Colombo", tipo: "Esame"),
        ]
        return OccupazioneAule(sedi: sedi, occupazioni: occupazioni, giorno: .now)
    }

    private static func oraSQL(_ d: Date) -> String {
        let c = Formats.calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d:00", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: Presenze (EasyBadge)

    static func frequenze() -> [Frequenza] {
        let righe = corsi.filter(\.primoSemestre).map { c -> String in
            let slot = slotPassati(c)
            let fatti = Double(slot.filter(\.presente).count) * 180
            let totale = Double(c.cfu * 8 * 60)
            let soglia = totale * 0.7
            return #"{"codice":"\#(c.codice)","nome":"\#(c.nome)","integrato":"","percentuale_conseguimento":0.7,"Frequentate":\#(fatti),"OreFatte":\#(fatti),"OreDaFare":\#(max(totale - fatti, 0)),"OreLimite":\#(soglia),"Percentuale":\#(fatti / totale * 100),"Stato":"in_frequenza","aa":"\#(annoAccademico.prefix(4))/\#(annoInizio + 1)","NascondiConteggiAlloStudente":0}"#
        }
        return (try? JSONDecoder().decode([Frequenza].self, from: Data("[\(righe.joined(separator: ","))]".utf8))) ?? []
    }

    static func slot(codici: [String]) -> [SlotLezione] {
        let righe = corsi.filter { codici.contains($0.codice) }.flatMap { c in
            slotPassati(c).map { s in
                #"{"id":"\#(s.id)","inizio":"\#(sql(s.inizio))","fine":"\#(sql(s.fine))","svolta":"1","CodiceCorso":"\#(c.codice)","Modulo":"","Presenza":"\#(s.presente ? 1 : 0)","Timestamp":"\#(s.presente ? sql(s.inizio.addingTimeInterval(1800)) : "")","Nota":""}"#
            }
        }
        return (try? JSONDecoder().decode([SlotLezione].self, from: Data("[\(righe.joined(separator: ","))]".utf8))) ?? []
    }

    private static func slotPassati(_ c: Corso) -> [(id: String, inizio: Date, fine: Date, presente: Bool)] {
        lezioni(file: "\(c.codice)_1-semestre.xml")
            .filter { $0.fine < .now && !$0.annullato && $0.id != "demo-ora" }
            .enumerated()
            .map { i, l in (l.id, l.inizio, l.fine, (i + c.cfu) % 5 != 0) }
    }

    private static func sql(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = Formats.rome; f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    static let obbligoFrequenza = ObbligoFrequenza(
        percentuale: 70, url: URL(string: "https://apps.unimi.it/files/manifesti/ita_manifesto_NCNof1_demo.pdf")!,
        coorte: "\(Formats.currentAcademicYear(now: Formats.calendar.date(byAdding: .year, value: -1, to: .now) ?? .now))")

    // MARK: UNIMIA

    static func tasse() -> SituazioneTasse {
        let cal = Formats.calendar
        let settembre = Formats.dayDMY("15-09-\(annoInizio)")
        let ottobre = Formats.dayDMY("20-10-\(annoInizio)")
        var scadenza = Formats.dayDMY("02-02-\(annoInizio + 1)") ?? .now
        if scadenza < .now { scadenza = cal.date(byAdding: .month, value: 2, to: .now) ?? scadenza }
        return SituazioneTasse(
            annoAccademico: annoAccademico.replacingOccurrences(of: "/", with: " - 20"),
            righe: [
                RigaTassa(causale: "CONTRIB. REGIONE LOMBARDIA", rata: "1", dovuto: 140, pagato: 140, dataPagamento: settembre, daPagare: 0),
                RigaTassa(causale: "IMPOSTA DI BOLLO", rata: "1", dovuto: 16, pagato: 16, dataPagamento: settembre, daPagare: 0),
                RigaTassa(causale: "CONTRIBUTO ONNICOMPRENSIVO", rata: "1", dovuto: 612, pagato: 612, dataPagamento: ottobre, daPagare: 0),
            ],
            messaggi: [
                "E' possibile pagare la seconda rata con Pago PA un mese prima della scadenza \(Formats.dmyString(scadenza).replacingOccurrences(of: "-", with: "/")).",
                "La tua posizione amministrativa risulta regolare.",
            ],
            anniPrecedenti: "Nessun debito per gli anni accademici precedenti.")
    }

    static func libretto() -> Libretto {
        let colonne = ["Attività didattica", "CFU", "Voto", "Data"]
        let anno = annoInizio
        let righe: [[String: String]] = [
            ["Attività didattica": "Neuropsicologia clinica", "CFU": "9", "Voto": "28", "Data": "18/01/\(anno)"],
            ["Attività didattica": "Psicometria avanzata", "CFU": "6", "Voto": "30 e lode", "Data": "02/02/\(anno)"],
            ["Attività didattica": "Neuroscienze cognitive", "CFU": "9", "Voto": "27", "Data": "14/06/\(anno)"],
            ["Attività didattica": "Psicologia fisiologica", "CFU": "6", "Voto": "29", "Data": "03/07/\(anno)"],
            ["Attività didattica": "Inglese scientifico", "CFU": "3", "Voto": "Idoneo", "Data": "10/09/\(anno)"],
        ]
        return Libretto(intestazione: "Dettaglio carriera - Laurea magistrale in \(nomeCorso) - matr. 12345A",
                        vuoto: false, colonne: colonne, righe: righe)
    }

    // MARK: SIFA

    static func esamiIscrivibili() -> [EsameIscrivibile] {
        corsi.enumerated().map { i, c in EsameIscrivibile(codice: "NCN0\(i + 1)0", descrizione: c.nome.uppercased(), crediti: c.cfu) }
    }

    static func appelliDisponibili(_ esame: EsameIscrivibile) -> SelezioneAppello {
        let c = corsi.first { $0.nome.uppercased() == esame.descrizione }
        let futuri = appelli().filter { $0.insegnamento == c?.nome && !$0.passato }
        return SelezioneAppello(
            esame: esame.descrizione,
            appelli: futuri.enumerated().map { i, a in
                AppelloIscrivibile(id: i, righe: ["\(a.inizio.italiano(date: .complete, time: .omitted)) · ore \(Formats.time(a.inizio))",
                                                  "\(a.tipo) · \(a.aula), \(a.sede)", "Docente: \(c?.docente ?? "")"],
                                   data: a.inizio, campoScelta: nil, valoreScelta: nil, link: nil)
            },
            messaggio: futuri.isEmpty ? "Nessun appello disponibile." : nil)
    }

    static func prenotazioni() -> TabellaSifa {
        guard let a = appelli().first(where: { !$0.passato && $0.insegnamento == corsi[1].nome }) else {
            return TabellaSifa(vuota: true, messaggio: "Nessun esame presente", colonne: [], righe: [])
        }
        let data = Formats.dmyString(a.inizio).replacingOccurrences(of: "-", with: "/")
        return TabellaSifa(vuota: false, messaggio: nil, colonne: ["Esame", "Data", "Ora", "Aula"],
                           righe: [["Esame": a.insegnamento.uppercased(), "Data": data, "Ora": Formats.time(a.inizio), "Aula": "\(a.aula) - \(a.sede)"]])
    }

    static let esitiFinali = TabellaSifa(vuota: true, messaggio: "Non è presente nessun esito in attesa di accettazione o rifiuto.",
                                         colonne: [], righe: [])

    // MARK: Documenti

    /// PDF dimostrativo (manifesti, curriculum, materiali dei corsi): una pagina con titolo e testo.
    static func pdf(titolo: String, testo: String) throws -> URL {
        let nome = titolo.replacingOccurrences(of: #"[/:\\?%*|"<>]"#, with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appending(path: "Demo-\(nome).pdf")
        let pagina = CGRect(x: 0, y: 0, width: 595, height: 842)
        let dati = UIGraphicsPDFRenderer(bounds: pagina).pdfData { ctx in
            ctx.beginPage()
            let titoloAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
            let testoAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            (titolo as NSString).draw(in: CGRect(x: 56, y: 60, width: 483, height: 60), withAttributes: titoloAttr)
            (testo as NSString).draw(in: CGRect(x: 56, y: 130, width: 483, height: 650), withAttributes: testoAttr)
        }
        try dati.write(to: url, options: .atomic)
        return url
    }
}
