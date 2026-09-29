import Foundation

// MARK: - Alberi corsi

/// `api_profilo_aa_scuola_tipo_cdl_pd.php` (orario) e `api_profilo_esami_scuola_tipo_cdl.php` (esami):
/// scuola → tipo di laurea → corso → periodi. Nell'albero ESAMI manca `code` (il codice lettera è in `valore`)
/// e `pub_periodi` sono gli anni di corso ("1 anno", …). Nell'albero ORARIO i periodi sono semestri,
/// trimestri, quadrimestri o "annuale".
nonisolated struct AgendaScuola: Codable, Sendable, Hashable {
    let label: String                 // "Psicologia"
    let valore: StringOrInt           // `0` (Int) nella prima voce, stringa nelle altre
    let lauree: [AgendaLaurea]
    enum CodingKeys: String, CodingKey { case label, valore, lauree = "elenco_lauree" }
}
nonisolated struct AgendaLaurea: Codable, Sendable, Hashable {
    let tipo: String                  // "CDS MAGISTRALE", "CDS TRIENNALE", "CDS MAGISTRALE A CICLO UNICO", …
    let cdl: [AgendaCdl]
    enum CodingKeys: String, CodingKey { case tipo, cdl = "elenco_cdl" }
}
nonisolated struct AgendaCdl: Codable, Sendable, Hashable {
    let label: String                 // "NEUROPSICOLOGIA CLINICA E SPERIMENTALE (Classe LM-51 R)"
    let valore: String                // orario: "7987" (id cdl, stringa) — esami: "DBD"
    let code: String?                 // orario: "DBD" — esami: assente
    let periodi: [AgendaPeriodo]
    let codiceFacolta: String         // "psico_sani"
    enum CodingKeys: String, CodingKey { case label, valore, code, periodi = "pub_periodi", codiceFacolta = "codice_facolta" }

    /// Codice lettera del corso in entrambi gli alberi.
    var codiceLettera: String { code ?? valore }
}
nonisolated struct AgendaPeriodo: Codable, Sendable, Hashable, Identifiable {
    let label: String                 // "primo semestre" / "1 anno"
    let valore: String                // "1-semestre" / "1"
    let id: String                    // "976" (= periodo_didattico) / "1"
}

/// Corso scelto per Orario o Esami: di default quello dello studente (match sul codice UNIMIA), modificabile.
nonisolated struct CorsoSelezionato: Codable, Sendable, Hashable {
    let scuola: String
    let tipo: String
    let cdl: AgendaCdl
}

// MARK: - Insegnamenti

/// `api_profilo_lista_insegnamenti.php?cdl=7987&periodo_didattico=976`.
/// `anno` e `crediti` sono stringhe; `codice_cdl` è il codice lettera "DBD".
nonisolated struct InsegnamentoAgenda: Codable, Sendable, Hashable, Identifiable {
    let nome: String          // "Colloquio e processo anamnestico in neuropsicologia"
    let codice: String        // "DBD-28_1"
    let docente: String       // "Verdi Anna, Neri Luca"
    let id: String            // "498664_1"
    let anno: String          // "1"
    let codiceFacolta: String // "psico_sani"
    let file: String          // "2026/DBD-28_1_1-semestre.xml"
    let codiceCdl: String     // "DBD"
    let crediti: String       // "6"
    let terzaRiga: String     // "Unico" (curriculum)
    let erogante: String      // ""
    enum CodingKeys: String, CodingKey {
        case nome, codice, docente, id, anno, file, crediti, erogante
        case codiceFacolta = "codice_facolta", codiceCdl = "codice_cdl", terzaRiga = "terza_riga"
    }
}

/// Configurazione persistita: corso dell'utente, scelte di Orario/Esami e insegnamenti attivati per corso+periodo.
nonisolated struct AgendaConfig: Codable, Sendable {
    let codiceCorso: String                        // "DBD" (da UNIMIA)
    let annoStudente: Int                          // 1
    let mioCorsoOrario: CorsoSelezionato           // corso dell'utente nell'albero orario (match su `code`)
    let mioCorsoEsami: CorsoSelezionato            // corso dell'utente nell'albero esami (match su `valore`)
    var corsoOrario: CorsoSelezionato              // default: corso dell'utente
    var periodoOrario: String?                     // id periodo scelto nella pillola (nil = automatico)
    var corsoEsami: CorsoSelezionato               // default: corso dell'utente (albero esami)
    var annoEsami: String?                         // valore anno scelto nella pillola (nil = anno dello studente)
    var insegnamenti: [String: [InsegnamentoAgenda]] // chiave "cdlId|periodoId"
    var attivati: [String: Set<String>]            // chiave cdlId → codici attivati (tutti i periodi)
    var aggiornato: Date

    static func key(_ cdl: String, _ periodo: String) -> String { "\(cdl)|\(periodo)" }

    /// Periodo in corso secondo il calendario accademico (semestri, trimestri, quadrimestri, annuale).
    static func periodoAttuale(_ periodi: [AgendaPeriodo], now: Date = .now) -> AgendaPeriodo? {
        let m = Formats.calendar.component(.month, from: now)
        func mesi(_ label: String) -> Set<Int> {
            let l = label.lowercased()
            if l.contains("annual") { return Set(1...12) }
            let ordine = l.contains("primo") ? 1 : l.contains("secondo") ? 2 : l.contains("terzo") ? 3 : 0
            if l.contains("trimestre") { return [[], [9, 10, 11, 12], [1, 2, 3], [4, 5, 6, 7, 8]][ordine].reduce(into: Set<Int>()) { $0.insert($1) } }
            if l.contains("quadrimestre") { return [[], [9, 10, 11, 12, 1], [2, 3, 4, 5], [6, 7, 8]][ordine].reduce(into: Set<Int>()) { $0.insert($1) } }
            return [[], [8, 9, 10, 11, 12, 1], [2, 3, 4, 5, 6, 7], []][ordine].reduce(into: Set<Int>()) { $0.insert($1) }
        }
        return periodi.first { mesi($0.label).contains(m) } ?? periodi.first
    }

    /// Insegnamenti attivati per il corso dell'utente (usati da Oggi e Registrazioni).
    var insegnamentiUtenteAttivati: [InsegnamentoAgenda] {
        let cdl = mioCorsoOrario.cdl.valore
        let on = attivati[cdl] ?? []
        var seen = Set<String>()
        return insegnamenti.filter { $0.key.hasPrefix(cdl + "|") }.values.flatMap { $0 }
            .filter { on.contains($0.codice) && seen.insert($0.codice).inserted }
            .sorted { $0.nome < $1.nome }
    }
}

// MARK: - Orario (live)

/// XML da `App/zipped.php?file=2026/DBD-29_1_1-semestre.xml` (Content-Encoding gzip, decompresso da URLSession).
/// `<Giorno id Data="29-09-2026" OraInizio="14:30" OraFine="18:30" Annullato="1" Aula AulaCodice Sede Tipo Notes …/>`.
/// Un file inesistente risponde 200 con corpo vuoto → nessuna lezione.
nonisolated struct Lezione: Sendable, Hashable, Identifiable {
    let id: String               // Giorno@id "6482331"
    let codiceInsegnamento: String // Insegnamento@CodiceGenerale "DBD-29"
    let insegnamento: String     // Insegnamento@Nome
    let docente: String          // DocenteTitolare@Nome+@Cognome → "Mario Bianchi"
    let inizio: Date             // Giorno@Data + @OraInizio
    let fine: Date               // Giorno@Data + @OraFine
    let aula: String             // Giorno@Aula "Sala Conferenze"
    let aulaCodice: String       // Giorno@AulaCodice "9999981-Conf" (EasyRoom: "9999981@Conf")
    let sede: String             // Giorno@Sede "Istituto Auxologico Italiano"
    let annullato: Bool          // Giorno@Annullato "1"
    let tipo: String             // Giorno@Tipo "Lezione"
    let note: String             // Giorno@Notes + @NoteAula + @NoteSettimanali
}

nonisolated struct OrarioInsegnamento: Sendable {
    let dataInizio: Date?        // Orario@DataInizio "28-09-2026"
    let dataFine: Date?          // Orario@DataFine "18-12-2026"
    let festivita: [Date]        // GiornoFestivita@Giorno "2026-12-07" (formato ISO, diverso da Data)
    let lezioni: [Lezione]
}

// MARK: - Appelli (live)

/// `test_call.php?view=easytest&include=et_cdl&et_er=1&datefrom=…&dateto=…&esami_cdl[]=DBD|1`:
/// `{ "Insegnamenti": { "DBD-7_1": { "DatiInsegnamento": {…}, "DatiDocente": {"<matr>": {…}}, "Appelli": [ … ] } } }`.
/// Senza appelli `"Insegnamenti": []`.
nonisolated struct EsamiResponse: Decodable, Sendable {
    let insegnamenti: PHPDictionary<EsameInsegnamento>
    enum CodingKeys: String, CodingKey { case insegnamenti = "Insegnamenti" }
}
nonisolated struct EsameInsegnamento: Decodable, Sendable {
    let dati: DatiInsegnamento
    let docenti: PHPDictionary<DocenteAgenda>?
    let appelli: [AppelloRaw]
    enum CodingKeys: String, CodingKey { case dati = "DatiInsegnamento", docenti = "DatiDocente", appelli = "Appelli" }
}
nonisolated struct DatiInsegnamento: Decodable, Sendable {
    let codice: String           // "DBD-7_1"
    let codiceGenerale: String   // "DBD-7"
    let nome: String
    let crediti: String          // "9"
    enum CodingKeys: String, CodingKey { case codice = "Codice", codiceGenerale = "CodiceGenerale", nome = "Nome", crediti = "Crediti" }
}
nonisolated struct DocenteAgenda: Decodable, Sendable {
    let nome: String; let cognome: String
    enum CodingKeys: String, CodingKey { case nome = "Nome", cognome = "Cognome" }
}
nonisolated struct AppelloRaw: Decodable, Sendable {
    let data: String             // "03-09-2026"
    let oraInizio: String        // "09:00"
    let oraFine: String          // "12:00"
    let aula: String             // "Cono 2"
    let sede: String             // "Noto"
    let aulaCodici: [String]     // AulaCodice ["33230#4001"] = EasyRoom room@room_code
    let passato: Bool            // true
    let timestamp: Int?          // 1788418800
    let tipo: String             // "Esame"
    let annullato: Bool          // event_Annullato "0"
    let eventId: String          // "6347301"
    let note: String             // event_PublicNotes / Notes
    enum CodingKeys: String, CodingKey {
        case data = "Data", oraInizio = "OraInizio", oraFine = "OraFine", aula = "Aula", sede = "Sede"
        case aulaCodice = "AulaCodice", passato = "Passato", timestamp = "Timestamp"
        case tipo = "Tipo", annullato = "event_Annullato", eventId = "event_id", notes = "Notes", publicNotes = "event_PublicNotes"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = c.string(.data); oraInizio = c.string(.oraInizio); oraFine = c.string(.oraFine)
        aula = c.string(.aula); sede = c.string(.sede)
        aulaCodici = (try? c.decode([String].self, forKey: .aulaCodice)) ?? [c.string(.aulaCodice)].filter { !$0.isEmpty }
        passato = (try? c.decode(Bool.self, forKey: .passato)) ?? c.flag(.passato)
        timestamp = try? c.decode(Int.self, forKey: .timestamp)
        tipo = c.string(.tipo); annullato = c.flag(.annullato); eventId = c.string(.eventId)
        note = [c.string(.publicNotes), c.string(.notes)].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// Appello normalizzato per la UI.
nonisolated struct Appello: Sendable, Hashable, Identifiable {
    let id: String               // event_id
    let codiceInsegnamento: String // "DBD-28_1"
    let insegnamento: String
    let docenti: [String]        // "Nome Cognome"
    let inizio: Date             // Data + OraInizio (coerente con Timestamp)
    let fine: Date?
    let aula: String
    let sede: String
    let aulaCodici: [String]
    let tipo: String
    let passato: Bool
    let annullato: Bool
    let note: String
}
