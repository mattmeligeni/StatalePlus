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
