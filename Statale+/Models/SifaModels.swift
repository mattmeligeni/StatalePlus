import Foundation

/// App SIFA usate (idApplicazione hpsifa fra parentesi). Ogni app è un service CAS separato.
nonisolated enum SifaApp: String, Sendable, CaseIterable {
    case iscrizioneEsami = "foIscrizioneEsami"   // 1580
    case verbalizzazione = "foVerbalizzazione"   // 1584
    case pagamenti = "fo_pagamenti"              // 1544

    var root: String { rawValue }
    var checkLogin: URL { URL(string: "https://studente.unimi.it/\(rawValue)/checkLogin.asp")! }
    var officialURL: URL { URL(string: "https://studente.unimi.it/\(rawValue)/")! }
}

/// "Esami del tuo corso di studio" (`foIscrizioneEsami/esamiPack/EsamiNonSostenutiDelCorsoPage`):
/// `table.smart-table` con intestazioni "Codice" | "Descrizione" | "Crediti" | "" e pulsante "Iscrizione" per riga.
/// I codici SIFA ("DBD0A0") non coincidono con quelli Agenda/Ariel ("DBD-28"): i collegamenti si fanno per nome.
nonisolated struct EsameIscrivibile: Sendable, Hashable, Identifiable {
    var id: String { codice }
    let codice: String          // td[0] "F-001-" → "F-001"
    let descrizione: String     // td[1] "COLLOQUIO E PROCESSO ANAMNESTICO IN NEUROPSICOLOGIA"
    let crediti: Int            // td[2] "6"
    /// td[3] `a[href]` "./EsamiNonSostenutiDelCorsoPage?11-1.ILinkListener-form-listEsamiPanel-table-body-rows-1-cells-4-cell-actionButton".
    /// URL Wicket legato alla pagina viva (`?11`): è l'azione "Iscrizione" da seguire nella stessa sessione.
    let iscrizioneListenerPath: String?
}

/// Tabella SIFA generica (prenotazioni confermate, esiti finali).
/// Casi vuoti reali: "Nessun esame presente" e "Non è presente nessun esito in attesa di accettazione o rifiuto.".
nonisolated struct TabellaSifa: Sendable {
    let vuota: Bool
    let messaggio: String?
    let colonne: [String]
    let righe: [[String: String]]
}

/// Appello prenotato ricavato da una riga di `EsamiIscrizioniConfermatePage`.
/// Le colonne esatte di una prenotazione non sono note: si individuano la data (dd/MM/yyyy o dd-MM-yyyy,
/// con ora opzionale) e il nome dell'esame per euristica sulle intestazioni.
nonisolated struct Prenotazione: Sendable, Hashable, Identifiable {
    var id: String { "\(esame)|\(data.timeIntervalSince1970)" }
    let esame: String
    let data: Date
    let dettagli: [String: String]

    static func from(_ tabella: TabellaSifa) -> [Prenotazione] {
        tabella.righe.compactMap { riga in
            var giorno: Date?
            var ora: String?
            for v in riga.values {
                if giorno == nil, let d = v.firstMatch(#"(\d{2}[/-]\d{2}[/-]\d{4})"#) {
                    giorno = Formats.daySlash(d.replacingOccurrences(of: "-", with: "/"))
                }
                if ora == nil { ora = v.firstMatch(#"\b(\d{1,2}[:.]\d{2})\b"#)?.replacingOccurrences(of: ".", with: ":") }
            }
            guard let giorno else { return nil }
            let nameKey = riga.keys.first { k in ["esame", "insegnamento", "descrizione", "attività"].contains { k.lowercased().contains($0) } }
            let nome = nameKey.flatMap { riga[$0] } ?? riga.values.max { $0.count < $1.count } ?? ""
            let data = ora.flatMap { Formats.at(giorno, $0) } ?? giorno
            return Prenotazione(esame: nome, data: data, dettagli: riga)
        }
        .sorted { $0.data < $1.data }
    }
}
