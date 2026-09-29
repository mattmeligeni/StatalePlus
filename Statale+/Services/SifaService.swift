import Foundation

/// SIFA online (Wicket, stateful): pagine "montate a classe", mai URL `?N` effimeri.
actor SifaService {
    private let cas: CASSession
    init(cas: CASSession) { self.cas = cas }

    /// "Esami del tuo corso di studio" (esami a cui ci si può iscrivere).
    func esamiIscrivibili() async throws -> [EsameIscrivibile] {
        let r = try await cas.sifaPage(.iscrizioneEsami, path: "esamiPack/EsamiNonSostenutiDelCorsoPage")
        return try SifaParser.esamiNonSostenuti(html: r.text)
    }

    func prenotazioni() async throws -> TabellaSifa {
        let r = try await cas.sifaPage(.iscrizioneEsami, path: "esamiPack/EsamiIscrizioniConfermatePage")
        return try SifaParser.tabella(html: r.text, vuotoMarker: "Nessun esame presente")
    }

    func esitiFinali() async throws -> TabellaSifa {
        let r = try await cas.sifaPage(.verbalizzazione, path: "esitiFinali")
        return try SifaParser.tabella(html: r.text, vuotoMarker: "Non è presente nessun esito")
    }

    /// Azione "Iscrizione" di una riga di "Esami del tuo corso di studio".
    /// Flusso da completare: ricaricare `EsamiNonSostenutiDelCorsoPage` nella stessa sessione Wicket,
    /// seguire l'`ILinkListener` della riga (relativo alla pagina viva), scegliere l'appello e confermare.
    func iscrivi(_ esame: EsameIscrivibile) async throws -> String {
        throw SifaError.iscrizioneNonDisponibile
    }
}

nonisolated enum SifaError: LocalizedError {
    case iscrizioneNonDisponibile
    var errorDescription: String? { "L'iscrizione dall'app non è ancora attiva." }
}
