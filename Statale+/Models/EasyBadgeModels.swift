import Foundation

// MARK: - Frequenze

/// POST `/easybadge-new/api/corso_iscritti.php`, body `{"Matricola":"12345a"}`.
/// Risposta: `{ "12345a": { "<nome corso>": [ { … } ] } }` (chiavi dinamiche).
/// I campi "Ore…" sono in MINUTI e `OreDaFare` è il residuo: Frequentate=240 (una lezione di 4 h),
/// OreFatte+OreDaFare = 2640 = 11 slot × 240, Percentuale 9.09 = 240/2640, OreLimite 1848 = 0.7 × 2640.
nonisolated struct Frequenza: Decodable, Sendable, Hashable, Identifiable {
    var id: String { codice }
    let codice: String               // "DBD-28_1"
    let nome: String                 // "Colloquio e processo anamnestico in neuropsicologia"
    let integrato: String            // "…_182"
    let soglia: Double               // percentuale_conseguimento 0.7
    let minutiFrequentati: Double    // Frequentate 240
    let minutiFatti: Double          // OreFatte 240
    let minutiDaFare: Double         // OreDaFare 2400 (residuo)
    let minutiSoglia: Double         // OreLimite 1847.9999999999998
    let percentuale: Double          // Percentuale 9.09
    let stato: String                // "in_frequenza"
    let annoAccademico: String       // aa "2026/2027"
    let nascondiConteggi: Bool       // NascondiConteggiAlloStudente 0

    var minutiTotali: Double { minutiFatti + minutiDaFare }
    var sogliaRaggiunta: Bool { minutiFatti >= minutiSoglia && minutiSoglia > 0 }

    enum CodingKeys: String, CodingKey {
        case codice, nome, integrato, soglia = "percentuale_conseguimento", frequentate = "Frequentate"
        case oreFatte = "OreFatte", oreDaFare = "OreDaFare", oreLimite = "OreLimite", percentuale = "Percentuale"
        case stato = "Stato", aa, nascondi = "NascondiConteggiAlloStudente"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codice = c.string(.codice); nome = c.string(.nome); integrato = c.string(.integrato)
        soglia = c.double(.soglia); minutiFrequentati = c.double(.frequentate)
        minutiFatti = c.double(.oreFatte); minutiDaFare = c.double(.oreDaFare); minutiSoglia = c.double(.oreLimite)
        percentuale = c.double(.percentuale); stato = c.string(.stato); annoAccademico = c.string(.aa)
        nascondiConteggi = c.flag(.nascondi)
    }
}

// MARK: - Slot lezione

/// POST `/easybadge-new/api/timbrature.php`, body `{"Matricola":"12345a","Corsi":[{"codice":"DBD-28_1"}]}`.
/// Risposta: `{ "12345a": [ {…} ] }`. Tutti i valori sono stringhe.
nonisolated struct SlotLezione: Decodable, Sendable, Hashable, Identifiable {
    let id: String                   // "6536381"
    let inizio: Date                 // "2026-09-28 08:30:00"
    let fine: Date                   // "2026-09-28 12:30:00"
    let svolta: Bool                 // "1"
    let codiceCorso: String          // CodiceCorso "DBD-28_1"
    let modulo: String               // Modulo
    let presenza: Bool               // Presenza "1"
    let rilevataAlle: Date?          // Timestamp "2026-09-28 11:24:53" oppure ""
    let nota: String                 // Nota

    enum CodingKeys: String, CodingKey {
        case id, inizio, fine, svolta, codiceCorso = "CodiceCorso", modulo = "Modulo"
        case presenza = "Presenza", timestamp = "Timestamp", nota = "Nota"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id)
        guard let i = Formats.sqlDate(c.string(.inizio)), let f = Formats.sqlDate(c.string(.fine)) else {
            throw DecodingError.dataCorruptedError(forKey: .inizio, in: c, debugDescription: "data slot non valida")
        }
        inizio = i; fine = f
        svolta = c.flag(.svolta); codiceCorso = c.string(.codiceCorso); modulo = c.string(.modulo)
        presenza = c.flag(.presenza); rilevataAlle = Formats.sqlDate(c.string(.timestamp)); nota = c.string(.nota)
    }
}

// MARK: - Timbratura

/// POST `/easybadge-new/api/TimbratureApi.php`. Chiavi e struttura identiche alla richiesta reale:
/// `{"matricola_studente","codice_lezione","lingua":"it","autenticazione":true,"action":"CreateFromJSON",
///   "dati_addizionali":{"timestamp":<epoch ms>,"longitudine":0,"latitudine":0}}`.
/// Le coordinate restano a 0 come nella richiesta osservata: la posizione non viene usata.
nonisolated struct TimbraturaRequest: Encodable, Sendable {
    let matricola_studente: String
    let codice_lezione: String
    let lingua = "it"
    let autenticazione = true
    let action = "CreateFromJSON"
    let dati_addizionali: DatiAggiuntivi

    nonisolated struct DatiAggiuntivi: Encodable, Sendable {
        let timestamp: Int64         // epoch in millisecondi
        let longitudine: Double = 0
        let latitudine: Double = 0
    }

    init(matricola: String, codiceLezione: String, posto: String = "", timestamp: Date = .now) {
        matricola_studente = matricola
        codice_lezione = codiceLezione
        dati_addizionali = DatiAggiuntivi(timestamp: Int64((timestamp.timeIntervalSince1970 * 1000).rounded()))
    }
}

/// `{"result":"failure","message":"Il processo di rilevazione è stato interrotto dal docente, …"}`
nonisolated struct TimbraturaResult: Decodable, Sendable {
    let result: String
    let message: String
    var ok: Bool { ["success", "ok", "true"].contains(result.lowercased()) }
}

/// Contenuto del QR mostrato in aula → codice lezione. Formato del QR ancora da definire:
/// per ora il testo letto viene usato così com'è.
nonisolated enum QRLezione {
    static func codice(from payload: String) -> String { payload.trimmed }
}
