import Foundation

// MARK: - Offerta (cache persistibile)

/// `https://ariel.unimi.it/Offerta/myof`. Riga esterna:
/// `<tr><td class="col-md-1"><span class="tag …">DBD-29</span></td><td class="col-md-11"><p><strong>Titolo</strong>`.
/// Linguette anno: `a.nav-link[href="#sp-24576"] > small` "2026/27" → pannello `#sp-24576` con
/// `a.ariel[href="https://myariel.unimi.it/course/view.php?id=14057"]` e titolari `ul.list-user a`.
nonisolated struct InsegnamentoOfferta: Codable, Sendable, Hashable, Identifiable {
    var id: String { codice }
    let codice: String            // span.tag "DBD-29"
    let titolo: String            // strong "Neuroscienze cognitive dello sviluppo …"
    let courseId: String?         // "14057" (nil = "Nessun sito didattico attivato")
    let annoAccademico: String    // small "2026/27"
    let titolari: [String]        // "mario bianchi"
    var attivo: Bool { courseId != nil }
}

// MARK: - Struttura corso (core_courseformat_get_state)

/// Risposta `[{"error":false,"data":"<JSON come STRINGA>"}]`: doppia decodifica.
nonisolated struct MoodleAjaxEnvelope: Decodable, Sendable {
    let error: Bool
    let data: String?
    let exception: MoodleException?
}
nonisolated struct MoodleException: Decodable, Sendable {
    let message: String?
    let errorcode: String?
}

nonisolated struct CourseState: Codable, Sendable {
    let course: Course
    let section: [Section]
    let cm: [Module]

    nonisolated struct Course: Codable, Sendable {
        let id: String            // "14057" (stringa)
        let numsections: Int      // 2
        let baseurl: String       // "https://myariel.unimi.it/course/view.php?id=14057"
    }
    nonisolated struct Section: Codable, Sendable, Identifiable, Hashable {
        let id: String            // "69175"
        let number: Int           // 0
        let title: String         // "Informazioni sul corso"
        let cmlist: [String]      // ["206891","206892"]
        let visible: Bool
    }
    /// `module` è il tipo ("forum", "folder"); `modname` l'etichetta localizzata ("Forum", "Cartella").
    nonisolated struct Module: Codable, Sendable, Identifiable, Hashable {
        let id: String            // "206891"
        let name: String          // "Bacheca degli annunci"
        let modname: String       // "Forum"
        let module: String        // "forum"
        let url: String?          // "https://myariel.unimi.it/mod/forum/view.php?id=206891" (assente per le etichette)
        let visible: Bool
        let uservisible: Bool?
        let sectionid: String     // "69175"
    }

    func modules(in section: Section) -> [Module] {
        section.cmlist.compactMap { id in cm.first { $0.id == id } }
    }
}

// MARK: - Scheda insegnamento (cache persistibile)

/// `course/view.php?id=…`, blocco `section.block_w4info`: righe `<tr><td><h6> Etichetta: </h6></td><td>valore</td></tr>`.
nonisolated struct SchedaInsegnamento: Codable, Sendable {
    let annoAccademico: String?   // "Anno accademico:" → "2026/2027"
    let obiettivi: String?        // "Obiettivi formativi:"
    let periodo: String?          // "Periodo:" → "1° semestre"
    let lingua: String?           // "Lingua:" → "Italiano"
    let docenti: [String]         // "Docente:" → "Mario Bianchi (Lezioni)"
    let programmaURL: URL?        // "Insegnamento:" a → https://www.unimi.it/it/ugov/of/af20270000dbd-29
    let calendarioURL: URL?       // "Calendario lezioni:" a → orari.unimi.it/…&anno=2026&attivita%5b%5d=ECDBD-29_1
    let emailDocente: String?     // a[href^=mailto:]
    let cvDocenteURL: URL?        // a[href*=/cv/]
    /// Dal link calendario: "ECDBD-29_1" → "DBD-29_1", lo stesso codice delle API Agenda (`codice` degli insegnamenti).
    let codiceAgenda: String?
    let annoAgenda: String?       // "2026" (cartella del file XML "2026/DBD-29_1_1-semestre.xml")
    /// "Titolare del sito" (`#accordionDocenti`): contatti e ricevimento. Opzionale per le schede in cache
    /// salvate prima di questo campo (vengono riscaricate).
    var titolari: [TitolareSito]? = nil
}

/// Scheda "Contatti" + "Ricevimento" di un titolare del sito (blocco W4 della pagina del corso). Le righe dei contatti
/// si riconoscono dall'icona perché variano da docente a docente (un professore a contratto può avere solo email e CV).
nonisolated struct TitolareSito: Codable, Sendable, Hashable, Identifiable {
    var id: String { nome }
    let nome: String                 // p.font-weight-bold "Mario Rossi"
    let ruolo: String?               // p.font-italic "Professore Ordinario"
    let struttura: String?           // fa-university: "Dipartimento di Scienze Biomediche e Cliniche"
    let strutturaURL: URL?           //   a[href] sito del dipartimento
    let indirizzo: String?           // fa-map-marker con link a Google Maps: "Via … 74, 20157 Milano (MI)"
    let sede: String?                // fa-map-marker senza link: "Milano - Via …"
    let email: String?               // fa-envelope-o: a[href^=mailto:]
    let telefono: String?            // fa-phone
    let cvURL: URL?                  // fa-file-text: work.unimi.it/chiedove/cv/…pdf
    let chiEDoveURL: URL?            // fa-address-book: www.unimi.it/it/ugov/person/…
    let ricevimento: String?         // .div-ricevimento: "previo appuntamento e-mail"
    let luogoRicevimento: String?    //   dopo "Luogo ricevimento"

    /// "Mario Rossi (Lezioni)" della scheda → questo titolare, se il nome coincide.
    func corrisponde(a docente: String) -> Bool {
        docente.matchKey.hasPrefix(nome.matchKey) || nome.matchKey == docente.matchKey
    }
}

// MARK: - Contenuti modulo (live)

nonisolated struct FileMoodle: Sendable, Hashable, Identifiable {
    var id: URL { url }
    let nome: String      // testo di a[href*="/pluginfile.php/"]
    let url: URL
}

/// Pagina modulo: descrizione in `#intro` (= `.activity-description`), file `pluginfile.php`, discussioni se forum.
nonisolated struct ModuloDettaglio: Sendable {
    let descrizione: String
    let file: [FileMoodle]
    let discussioni: [DiscussioneForum]
}

/// `mod/forum/view.php`: `tr[data-region=discussion-list-item][data-discussionid=91954]`.
nonisolated struct DiscussioneForum: Codable, Sendable, Hashable, Identifiable {
    let id: String            // @data-discussionid "91954"
    let titolo: String        // th.topic a → "Inizio lezioni"
    let autore: String        // td.author .author-info > div → "Mario Bianchi"
    let creata: Date?         // time[id^=time-created]@data-timestamp "1790002145" (epoch)
    let ultimaAttivita: Date? // time[id^=time-modified]@data-timestamp
    let url: URL              // https://myariel.unimi.it/mod/forum/discuss.php?d=91954
}

/// `mod/forum/discuss.php?d=…`, `article[data-region=post]`: oggetto `[data-region-content=forum-post-core-subject]`,
/// testo `.post-content-container`, data `time[datetime]` "2026-09-21T16:49:05+02:00".
nonisolated struct PostForum: Sendable, Hashable, Identifiable {
    let id: String            // @data-post-id "107990"
    let oggetto: String       // "Inizio lezioni"
    let autore: String        // header a[href*="/user/view.php"]
    let data: Date?
    let testo: String
}

// MARK: - Partecipanti (live)

/// `user/index.php?id=…`, `table#participants tbody tr`. Colonne: "Seleziona tutto" | "Nome" | "Ruoli" | "Gruppi".
nonisolated struct Partecipante: Sendable, Hashable, Identifiable {
    let id: String            // th.c1 a[href*="user/view.php?id="] → id
    let nome: String          // span.userinitials@title
    let ruoli: String         // td.c2 → "Studente" / "Docente titolare"
    let gruppi: String        // td.c3
}

// MARK: - Valutazioni (live)

/// `grade/report/index.php?id=…`, `table.user-grade`: celle per classe `column-itemname`, `column-grade`, …
nonisolated struct VoceValutazione: Sendable, Hashable, Identifiable {
    var id: String { elemento }
    let elemento: String      // "Aggregazione dei voti Totale corso"
    let peso: String          // "-"
    let valutazione: String   // "-"
    let intervallo: String    // "0–0"
    let percentuale: String   // "-"
    let feedback: String      // ""
}

// MARK: - Calendario e notifiche (AJAX Moodle, live)

/// Evento del calendario Moodle: `core_calendar_get_calendar_upcoming_view` (prossimi ~21 giorni, tutti i corsi)
/// e `core_calendar_get_action_events_by_timesort` (consegne e quiz da fare, anche scaduti). Schema di Moodle 4.5;
/// al 30-09-2026 non c'erano eventi reali da osservare, quindi ogni campo tranne id e nome è opzionale.
nonisolated struct EventoMoodle: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let nome: String                  // name "Consegna relazione finale è in scadenza"
    let inizio: Date                  // timesort (eventi d'azione) o timestart
    let durata: TimeInterval          // timeduration (secondi)
    let tipo: String?                 // eventtype "due", "course", "user", "site", "open", "close"
    let modulo: String?               // modulename "assign", "quiz", "forum"
    let luogo: String?                // location
    let corso: String?                // course.fullname
    let courseId: String?             // course.id
    let url: URL?                     // url (pagina dell'attività su myAriel) o viewurl
    let azione: String?               // action.name "Aggiungi consegna"
    let scaduto: Bool                 // overdue

    private enum K: String, CodingKey {
        case id, name, timesort, timestart, timeduration, eventtype, modulename, location, course, url, viewurl, action, overdue
    }
    private enum CorsoK: String, CodingKey { case id, fullname }
    private enum AzioneK: String, CodingKey { case name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = Int(c.string(.id)) ?? 0
        nome = c.string(.name)
        let t = c.double(.timesort) > 0 ? c.double(.timesort) : c.double(.timestart)
        inizio = Date(timeIntervalSince1970: t)
        durata = c.double(.timeduration)
        tipo = c.string(.eventtype).nilSeVuota
        modulo = c.string(.modulename).nilSeVuota
        luogo = c.string(.location).nilSeVuota
        let corsoC = try? c.nestedContainer(keyedBy: CorsoK.self, forKey: .course)
        corso = corsoC?.string(.fullname).nilSeVuota
        courseId = corsoC?.string(.id).nilSeVuota
        // Prima la pagina dell'attività (consegna, quiz); la vista del giorno del calendario solo come ripiego.
        url = (c.string(.url).nilSeVuota ?? c.string(.viewurl).nilSeVuota).flatMap(URL.init(string:))
        azione = (try? c.nestedContainer(keyedBy: AzioneK.self, forKey: .action))?.string(.name).nilSeVuota
        scaduto = c.flag(.overdue)
    }
}

/// `message_popup_get_popup_notifications` (utente corrente con `useridto: 0`): `notifications[]` + `unreadcount`.
nonisolated struct NotificheMoodle: Decodable, Sendable {
    let notifiche: [NotificaMoodle]
    let nonLette: Int
    private enum K: String, CodingKey { case notifications, unreadcount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        notifiche = (try? c.decode([NotificaMoodle].self, forKey: .notifications)) ?? []
        nonLette = Int(c.string(.unreadcount)) ?? notifiche.filter { !$0.letta }.count
    }
}

nonisolated struct NotificaMoodle: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let oggetto: String               // subject
    let testo: String?                // smallmessage (o fullmessage)
    let url: URL?                     // contexturl: pagina a cui si riferisce (post del forum, consegna…)
    let etichettaURL: String?         // contexturlname "Titolo della discussione"
    let creata: Date                  // timecreated
    let letta: Bool                   // read
    let componente: String?           // component "mod_forum", "mod_assign", "moodle"

    private enum K: String, CodingKey {
        case id, subject, smallmessage, fullmessage, contexturl, contexturlname, timecreated, read, component
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = Int(c.string(.id)) ?? 0
        oggetto = c.string(.subject)
        testo = (c.string(.smallmessage).nilSeVuota ?? c.string(.fullmessage).nilSeVuota)?.trimmed
        url = c.string(.contexturl).nilSeVuota.flatMap(URL.init(string:))
        etichettaURL = c.string(.contexturlname).nilSeVuota
        creata = Date(timeIntervalSince1970: c.double(.timecreated))
        letta = c.flag(.read)
        componente = c.string(.component).nilSeVuota
    }

    /// `…/mod/forum/discuss.php?d=91954` → discussione apribile nell'app.
    var discussione: DiscussioneForum? {
        guard let url, url.path().hasSuffix("/mod/forum/discuss.php") else { return nil }
        return DiscussioneForum(id: url.query()?.firstMatch(#"d=(\d+)"#) ?? String(id), titolo: etichettaURL ?? oggetto,
                                autore: "", creata: creata, ultimaAttivita: creata, url: url)
    }
}

nonisolated extension String {
    var nilSeVuota: String? { trimmed.isEmpty ? nil : self }
}
