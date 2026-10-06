import Foundation

/// Ariel nella versione dimostrativa: un sito per corso con bacheca degli avvisi, materiali, esercitazioni,
/// partecipanti e valutazioni; scadenze e notifiche coerenti con gli avvisi.
nonisolated enum DatiDemoAriel {
    private static let moodle = "https://myariel.unimi.it"

    static func offerta() -> [InsegnamentoOfferta] {
        DatiDemo.corsi.map { c in
            InsegnamentoOfferta(codice: c.generale, titolo: c.nome, courseId: c.courseId,
                                annoAccademico: DatiDemo.annoAccademico, titolari: [c.docente.lowercased()])
        }
    }

    // MARK: Struttura del corso

    /// Identificativi dei moduli: courseId × 10 + n (1 annunci, 2 programma, 3 slide, 4 lezione, 5 consegna, 6 forum).
    static func struttura(courseId: String) -> CourseState? {
        guard DatiDemo.corso(courseId: courseId) != nil else { return nil }
        let base = (Int(courseId) ?? 0) * 10
        func m(_ n: Int, _ nome: String, _ tipo: String, _ etichetta: String, sezione: Int) -> CourseState.Module {
            let percorso = switch tipo { case "forum": "forum"; case "folder": "folder"; case "assign": "assign"; default: "resource" }
            return CourseState.Module(id: String(base + n), name: nome, modname: etichetta, module: tipo,
                                      url: "\(moodle)/mod/\(percorso)/view.php?id=\(base + n)", visible: true, uservisible: true,
                                      sectionid: String(base + sezione))
        }
        let moduli = [
            m(1, "Bacheca degli annunci", "forum", "Forum", sezione: 0),
            m(2, "Programma e modalità d'esame", "resource", "File", sezione: 0),
            m(3, "Slide delle lezioni", "folder", "Cartella", sezione: 1),
            m(4, "Letture consigliate", "resource", "File", sezione: 1),
            m(5, "Relazione di laboratorio", "assign", "Compito", sezione: 2),
            m(6, "Domande sul programma", "forum", "Forum", sezione: 2),
        ]
        return CourseState(
            course: .init(id: courseId, numsections: 3, baseurl: "\(moodle)/course/view.php?id=\(courseId)"),
            section: [
                .init(id: String(base), number: 0, title: "Informazioni sul corso", cmlist: [moduli[0].id, moduli[1].id], visible: true),
                .init(id: String(base + 1), number: 1, title: "Materiali delle lezioni", cmlist: [moduli[2].id, moduli[3].id], visible: true),
                .init(id: String(base + 2), number: 2, title: "Esercitazioni e domande", cmlist: [moduli[4].id, moduli[5].id], visible: true),
            ],
            cm: moduli)
    }

    static func scheda(courseId: String) -> SchedaInsegnamento? {
        guard let c = DatiDemo.corso(courseId: courseId) else { return nil }
        let email = c.docente.lowercased().replacingOccurrences(of: " ", with: ".") + "@unimi.example"
        return SchedaInsegnamento(
            annoAccademico: "\(DatiDemo.annoInizio)/\(DatiDemo.annoInizio + 1)",
            obiettivi: "Il corso fornisce le conoscenze teoriche e metodologiche su \(c.nome.lowercased()), con particolare attenzione alla valutazione clinica e alla lettura critica della letteratura scientifica.",
            periodo: c.primoSemestre ? "1° semestre" : "2° semestre", lingua: "Italiano",
            docenti: ["\(c.docente) (Lezioni)"], programmaURL: nil, calendarioURL: nil, emailDocente: email,
            cvDocenteURL: nil, codiceAgenda: c.codice, annoAgenda: String(DatiDemo.annoInizio),
            titolari: [TitolareSito(nome: c.docente, ruolo: "Professore Associato",
                                    struttura: "Dipartimento di Scienze Biomediche e Cliniche", strutturaURL: nil,
                                    indirizzo: nil, sede: "Milano - via Luigi Mangiagalli, 31", email: email, telefono: nil,
                                    cvURL: nil, chiEDoveURL: nil, ricevimento: "Su appuntamento via e-mail",
                                    luogoRicevimento: "Studio 3.12, terzo piano")])
    }

    // MARK: Moduli

    static func modulo(_ module: CourseState.Module) -> ModuloDettaglio {
        let id = Int(module.id) ?? 0
        guard let c = DatiDemo.corso(courseId: String(id / 10)) else { return ModuloDettaglio(descrizione: "", file: [], discussioni: []) }
        switch id % 10 {
        case 1:
            return ModuloDettaglio(descrizione: "Avvisi del docente: orari, aule, appelli e materiali.", file: [], discussioni: avvisi(c))
        case 2:
            return ModuloDettaglio(descrizione: "Programma dettagliato, testi d'esame e modalità di verifica.",
                                   file: [file(id, "Programma \(c.nome).pdf")], discussioni: [])
        case 3:
            return ModuloDettaglio(descrizione: "Le slide vengono caricate dopo ogni lezione.",
                                   file: (1...4).map { file(id, "Lezione \($0) - \(argomenti(c)[$0 - 1]).pdf") }, discussioni: [])
        case 4:
            return ModuloDettaglio(descrizione: "Articoli e capitoli di approfondimento.", file: [file(id, "Letture consigliate.pdf")], discussioni: [])
        case 5:
            return ModuloDettaglio(descrizione: "Relazione di massimo 5 pagine sull'esercitazione svolta in aula. Consegna in PDF entro la scadenza indicata.",
                                   file: [file(id, "Traccia della relazione.pdf")], discussioni: [])
        default:
            return ModuloDettaglio(descrizione: "Domande e risposte sul programma, aperte a tutti gli studenti.", file: [], discussioni: domande(c))
        }
    }

    private static func argomenti(_ c: DatiDemo.Corso) -> [String] {
        switch c.codice {
        case "NCN-12_1": ["Introduzione alle funzioni esecutive", "Modelli di controllo", "Memoria di lavoro", "Valutazione neuropsicologica"]
        case "NCN-14_1": ["Organizzazione del sistema nervoso", "Midollo spinale", "Tronco encefalico", "Corteccia cerebrale"]
        case "NCN-15_1": ["Principi di farmacologia", "Recettori e neurotrasmettitori", "Antipsicotici", "Antidepressivi"]
        case "NCN-17_1": ["Disegni sperimentali", "Statistica per le neuroscienze", "Neuroimmagini", "Etica della ricerca"]
        default: ["Il colloquio clinico", "L'anamnesi", "La restituzione", "Casi clinici"]
        }
    }

    private static func file(_ modulo: Int, _ nome: String) -> FileMoodle {
        let percorso = nome.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "file.pdf"
        return FileMoodle(nome: nome, url: URL(string: "\(moodle)/pluginfile.php/\(modulo)/mod_resource/content/1/\(percorso)")!)
    }

    // MARK: Forum

    /// Bacheca: un avviso recente (ieri) nei primi due corsi, così compare anche in Oggi.
    static func avvisi(_ c: DatiDemo.Corso) -> [DiscussioneForum] {
        let id = Int(c.courseId) ?? 0
        let indice = DatiDemo.corsi.firstIndex { $0.codice == c.codice } ?? 0
        var out = [
            discussione(id * 100 + 1, "Inizio delle lezioni e materiali", c.docente, giorniFa: 30),
            discussione(id * 100 + 2, "Date degli appelli dell'anno", c.docente, giorniFa: 12),
        ]
        if indice < 2 {
            out.insert(discussione(id * 100 + 3, indice == 0 ? "Lezione di mercoledì spostata in Aula 101" : "Slide della lezione di oggi caricate",
                                   c.docente, giorniFa: indice == 0 ? 1 : 0), at: 0)
        }
        return out
    }

    static func domande(_ c: DatiDemo.Corso) -> [DiscussioneForum] {
        let id = Int(c.courseId) ?? 0
        return [discussione(id * 100 + 11, "Bibliografia per i non frequentanti", "Giulia Verdi", giorniFa: 6),
                discussione(id * 100 + 12, "Chiarimento sulla relazione", "Luca Neri", giorniFa: 3)]
    }

    private static func discussione(_ id: Int, _ titolo: String, _ autore: String, giorniFa: Int) -> DiscussioneForum {
        let data = Formats.calendar.date(byAdding: .day, value: -giorniFa, to: .now)?.addingTimeInterval(-3600) ?? .now
        return DiscussioneForum(id: String(id), titolo: titolo, autore: autore, creata: data, ultimaAttivita: data,
                                url: URL(string: "\(moodle)/mod/forum/discuss.php?d=\(id)")!)
    }

    static func posts(_ d: DiscussioneForum) -> [PostForum] {
        let corso = DatiDemo.corso(courseId: String((Int(d.id) ?? 0) / 100))
        let docente = corso?.docente ?? d.autore
        let testo: String = switch d.titolo {
        case let t where t.contains("spostata"):
            "Care studentesse e cari studenti,\nper un problema tecnico la lezione di mercoledì si terrà in Aula 101 (Settore didattico Mangiagalli), stesso orario. Dalla settimana successiva torneremo in Aula 208.\n\nUn saluto,\n\(docente)"
        case let t where t.contains("Slide"):
            "Ho caricato le slide della lezione di oggi nella sezione \"Materiali delle lezioni\". Per la prossima volta leggete il capitolo 4 del manuale.\n\n\(docente)"
        case let t where t.contains("appelli"):
            "Sono state pubblicate le date degli appelli dell'anno accademico. Ricordate che l'iscrizione su SIFA chiude 5 giorni prima di ogni appello.\n\n\(docente)"
        case let t where t.contains("Inizio"):
            "Benvenuti! Le lezioni iniziano secondo l'orario pubblicato. In questo sito troverete programma, slide e avvisi: attivate le notifiche del forum.\n\n\(docente)"
        case let t where t.contains("Bibliografia"):
            "Buongiorno, per chi non frequenta sono previsti testi aggiuntivi? Grazie."
        default:
            "Buongiorno professoressa, la relazione va consegnata individualmente o in gruppo?"
        }
        var out = [PostForum(id: d.id + "1", oggetto: d.titolo, autore: d.autore, data: d.creata, testo: testo)]
        if d.autore != docente {
            out.append(PostForum(id: d.id + "2", oggetto: "Re: \(d.titolo)", autore: docente,
                                 data: d.creata?.addingTimeInterval(5 * 3600),
                                 testo: d.titolo.contains("Bibliografia")
                                     ? "Sì: i non frequentanti aggiungono il volume indicato nel programma, capitoli 5-8."
                                     : "Individualmente, massimo 5 pagine. Trovate la traccia nella sezione Esercitazioni."))
        }
        return out
    }

    // MARK: Partecipanti e valutazioni

    static func partecipanti(courseId: String) -> [Partecipante] {
        let docente = DatiDemo.corso(courseId: courseId)?.docente ?? "Docente"
        let studenti = ["Mario Rossi", "Giulia Verdi", "Luca Neri", "Sara Gallo", "Francesca Russo", "Alessandro Greco",
                        "Chiara Marino", "Matteo Bruno", "Elisa Costa", "Federico Rizzo", "Martina Lombardi", "Simone Barbieri"]
        return [Partecipante(id: "1", nome: docente, ruoli: "Docente titolare", gruppi: "")]
            + studenti.enumerated().map { i, n in Partecipante(id: String(i + 2), nome: n, ruoli: "Studente", gruppi: i % 2 == 0 ? "Gruppo A" : "Gruppo B") }
    }

    static func valutazioni(courseId: String) -> [VoceValutazione] {
        [VoceValutazione(elemento: "Relazione di laboratorio", peso: "40,00 %", valutazione: "27,00", intervallo: "0–30", percentuale: "90,00 %", feedback: "Ben argomentata."),
         VoceValutazione(elemento: "Quiz di autovalutazione", peso: "20,00 %", valutazione: "8,00", intervallo: "0–10", percentuale: "80,00 %", feedback: ""),
         VoceValutazione(elemento: "Aggregazione dei voti Totale corso", peso: "-", valutazione: "-", intervallo: "0–100", percentuale: "-", feedback: "")]
    }

    // MARK: Scadenze e notifiche

    static func scadenze() -> [EventoMoodle] {
        let c = DatiDemo.corsi
        func evento(_ id: Int, _ nome: String, giorni: Double, modulo: String, corso: DatiDemo.Corso, scaduto: Bool = false) -> String {
            let t = Int(Date.now.addingTimeInterval(giorni * 86400).timeIntervalSince1970)
            return #"{"id":\#(id),"name":"\#(nome)","timesort":\#(t),"timeduration":0,"eventtype":"due","modulename":"\#(modulo)","course":{"id":"\#(corso.courseId)","fullname":"\#(corso.nome)"},"url":"\#(moodle)/mod/\#(modulo)/view.php?id=\#((Int(corso.courseId) ?? 0) * 10 + 5)","overdue":"\#(scaduto ? 1 : 0)"}"#
        }
        let json = "[" + [
            evento(1, "Relazione di laboratorio è in scadenza", giorni: 4.2, modulo: "assign", corso: c[0]),
            evento(2, "Quiz di autovalutazione si chiude", giorni: 9.5, modulo: "quiz", corso: c[3]),
            evento(3, "Consegna esercizio sui recettori", giorni: 2.6, modulo: "assign", corso: c[2]),
            evento(4, "Questionario di inizio corso", giorni: -1.5, modulo: "assign", corso: c[4], scaduto: true),
        ].joined(separator: ",") + "]"
        return ((try? JSONDecoder().decode([EventoMoodle].self, from: Data(json.utf8))) ?? []).sorted { $0.inizio < $1.inizio }
    }

    /// Notifiche già lette nella demo (in memoria, come se fossero segnate sul sito).
    private static let lette = Lette()

    static func notifiche() async -> NotificheMoodle {
        let c = DatiDemo.corsi
        let lette = await lette.elenco
        func notifica(_ id: Int, _ oggetto: String, _ testo: String, discussione: DiscussioneForum?, ore: Double, letta: Bool) -> String {
            let t = Int(Date.now.addingTimeInterval(-ore * 3600).timeIntervalSince1970)
            let url = discussione.map { #","contexturl":"\#($0.url.absoluteString)","contexturlname":"\#($0.titolo)""# } ?? ""
            return #"{"id":\#(id),"subject":"\#(oggetto)","smallmessage":"\#(testo)","timecreated":\#(t),"read":"\#(letta || lette.contains(id) ? 1 : 0)","component":"\#(discussione == nil ? "mod_assign" : "mod_forum")"\#(url)}"#
        }
        let a0 = avvisi(c[0])[0], a1 = avvisi(c[1])[0], d = domande(c[4])[1]
        let json = "{\"notifications\":[" + [
            notifica(1, "\(c[0].nome): \(a0.titolo)", "Nuovo messaggio nella Bacheca degli annunci", discussione: a0, ore: 20, letta: false),
            notifica(2, "\(c[1].nome): \(a1.titolo)", "Nuovo messaggio nella Bacheca degli annunci", discussione: a1, ore: 3, letta: false),
            notifica(3, "Risposta a: \(d.titolo)", "\(c[4].docente) ha risposto alla tua domanda", discussione: d, ore: 60, letta: true),
            notifica(4, "Valutazione disponibile", "La relazione di laboratorio è stata valutata: 27/30", discussione: nil, ore: 120, letta: true),
        ].joined(separator: ",") + "]}"
        return try! JSONDecoder().decode(NotificheMoodle.self, from: Data(json.utf8))
    }

    static func segnaLetta(_ id: Int) async { await lette.aggiungi(id) }

    private actor Lette {
        var elenco: Set<Int> = []
        func aggiungi(_ id: Int) { elenco.insert(id) }
    }
}
