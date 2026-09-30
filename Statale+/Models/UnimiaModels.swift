import Foundation

// MARK: - Profilo (stabile → persistito)

/// UNIMIA home community (`/portal/server.pt/community/unimia/207/home/8993`) o portlet 212:
/// blocco `#div_studente` con coppie `<li><label>`. Il nome viene da `<h2>Home: NOME COGNOME</h2>`.
nonisolated struct Studente: Codable, Sendable, Hashable {
    let nome: String                 // h2 "Home: MARIO ROSSI" → "MARIO ROSSI"
    let matricola: String            // li "Matricola:" → "12345A"
    let tipoCorso: String            // li "Tipo di corso:" → "Corso di Laurea Magistrale"
    let corso: String                // li "Corso:" → "Neuropsicologia clinica e sperimentale (classe lm-51 r)"
    let codiceCorso: String          // li "Corso:" → "(codice: DBD, classe: …)" → "DBD"
    let anno: Int                    // li "Anno:" → "1"
    let statoIscrizione: String      // li "Tipo di iscrizione:" → "IN CORSO"
    let ultimoAnnoIscrizione: String // li "Ultimo anno di iscrizione:" → "2026 - 2027"
    let email: String                // #div_anagrafica li "Email:"

    /// EasyBadge vuole la matricola minuscola: `"Matricola": "12345a"`.
    var matricolaAPI: String { matricola.lowercased() }
}

/// Portlet 212 `#div_anagrafica`. Solo in memoria.
nonisolated struct Recapiti: Sendable, Hashable {
    let residenza: String   // li "Residenza:"
    let recapito: String    // li "Recapito:"
    let cellulare: String   // li "Cellulare:" (spazi finali nel sorgente → trim)
    let email: String       // li "Email:"
}

// MARK: - Tasse (live)

/// Portlet async 219 (`PTARGS_6_0_219_207_8993_43`), blocco `#div_situazione_amministrativa`.
nonisolated struct SituazioneTasse: Sendable {
    let annoAccademico: String   // `#lista-tasse h4` "Anno accademico: 2026 -\n 2027" → "2026 - 2027"
    let righe: [RigaTassa]       // `#lista-tasse table tbody tr`
    let messaggi: [String]       // `#lista-messaggi li`
    let anniPrecedenti: String?  // `#div_anni_precedenti`

    var totaleDovuto: Decimal { righe.reduce(0) { $0 + $1.dovuto } }
    var totalePagato: Decimal { righe.reduce(0) { $0 + $1.pagato } }
    var totaleDaPagare: Decimal { righe.reduce(0) { $0 + $1.daPagare } }

    /// Dagli avvisi: "È possibile pagare la seconda rata con PagoPA un mese prima della scadenza 02/02/2027…".
    /// Si ricava a quale rata si riferisce e se è già stata emessa (presente fra le righe).
    var prossimaScadenza: ScadenzaTasse? {
        let oggi = Formats.calendar.startOfDay(for: .now)
        let numeri = ["prima": "1", "seconda": "2", "terza": "3", "quarta": "4", "unica": "1"]
        return messaggi.compactMap { msg -> ScadenzaTasse? in
            guard let d = msg.firstMatch(#"scadenza\s+(\d{2}/\d{2}/\d{4})"#, options: .caseInsensitive).flatMap(Formats.daySlash),
                  d >= oggi else { return nil }
            let rata = msg.firstMatch(#"\b(prima|seconda|terza|quarta|unica)\s+rata\b"#, options: .caseInsensitive)?.lowercased()
            let emessa = rata.flatMap { numeri[$0] }.map { n in righe.contains { $0.rata == n } } ?? true
            // Solo ciò che l'avviso dice: nessuna data calcolata.
            let pagoPA = msg.range(of: #"pago\s?pa"#, options: [.regularExpression, .caseInsensitive]) != nil
            let unMesePrima = msg.range(of: "un mese prima della scadenza", options: .caseInsensitive) != nil
            return ScadenzaTasse(data: d, rata: rata, emessa: emessa, pagoPA: pagoPA, unMesePrima: unMesePrima)
        }
        .min { $0.data < $1.data }
    }
}

/// Scadenza ricavata dagli avvisi delle tasse.
nonisolated struct ScadenzaTasse: Sendable, Hashable {
    let data: Date            // 02/02/2027
    let rata: String?         // "seconda"
    let emessa: Bool          // false se la rata non è ancora fra le righe
    let pagoPA: Bool          // l'avviso cita PagoPA
    let unMesePrima: Bool     // "…con PagoPA un mese prima della scadenza…"

    /// "Seconda rata non ancora emessa · scadenza 2 febbraio 2027"
    var descrizione: String {
        let giorno = data.formatted(.dateTime.day().month(.wide).year().locale(Formats.it))
        let nome = rata.map { "\($0.prefix(1).uppercased())\($0.dropFirst()) rata" } ?? "Prossimo pagamento"
        return emessa ? "\(nome) · scadenza \(giorno)" : "\(nome) non ancora emessa · scadenza \(giorno)"
    }

    /// "Pagabile con PagoPA da un mese prima della scadenza", come scritto negli avvisi.
    var nota: String? {
        guard pagoPA else { return nil }
        return unMesePrima ? "Pagabile con PagoPA da un mese prima della scadenza" : "Pagabile con PagoPA"
    }
}

/// Intestazioni reali: "Causale tasse" | "Rata" | "Importo dovuto" | "Importo pagato" | "Data pagamento" | "Importo da pagare".
nonisolated struct RigaTassa: Sendable, Hashable, Identifiable {
    var id: String { "\(causale)|\(rata)" }
    let causale: String        // "CONTRIB. REGIONE LOMBARDIA     " → trim
    let rata: String           // "1 " → "1"
    let dovuto: Decimal        // "130 euro"
    let pagato: Decimal        // "130 euro"
    let dataPagamento: Date?   // "11-09-2026 "
    let daPagare: Decimal      // "0 euro"
}

// MARK: - Carriera (live)

/// Gateway Plumtree del portlet 209 (`#div_esami_studente`). Con libretto vuoto la pagina dice
/// "Non hai sostenuto alcun esame."; le righe di un libretto popolato sono lette come {intestazione: valore}.
nonisolated struct Libretto: Sendable {
    let intestazione: String            // "Dettaglio carriera - Laurea magistrale in … - matr. 12345A"
    let vuoto: Bool
    let colonne: [String]
    let righe: [[String: String]]
}

/// Portlet 240 (`#div_verbali_web`): "Non hai esiti d'esame in attesa di accettazione".
nonisolated struct EsitiInAttesa: Sendable {
    let inAttesa: Bool
    let messaggio: String
}

/// Portlet 310: "Non risultano iscrizioni attive."
nonisolated struct StatoIscrizioniAppelli: Sendable {
    let iscrizioniAttive: Bool
    let messaggio: String
}
