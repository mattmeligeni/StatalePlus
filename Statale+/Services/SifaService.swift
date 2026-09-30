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

    /// Pulsante "Iscrizione" di "Esami del tuo corso di studio": ricarica la pagina (il link vale solo per la
    /// versione appena generata, `?N`) e segue il link della riga → "Selezione appello". Solo lettura (GET).
    func appelliDisponibili(_ esame: EsameIscrivibile) async throws -> SelezioneAppello {
        let lista = try await cas.sifaPage(.iscrizioneEsami, path: "esamiPack/EsamiNonSostenutiDelCorsoPage")
        guard let href = SifaParser.linkIscrizione(html: lista.text, codice: esame.codice),
              let url = URL(string: href, relativeTo: lista.url)?.absoluteURL else {
            throw SifaError.esameNonTrovato
        }
        let r = try await cas.sifaFollow(.iscrizioneEsami, url: url)
        return try SifaParser.selezioneAppello(html: r.text)
    }

    func prenotazioni() async throws -> TabellaSifa {
        let r = try await cas.sifaPage(.iscrizioneEsami, path: "esamiPack/EsamiIscrizioniConfermatePage")
        return try SifaParser.tabella(html: r.text, vuotoMarker: "Nessun esame presente")
    }

    func esitiFinali() async throws -> TabellaSifa {
        let r = try await cas.sifaPage(.verbalizzazione, path: "esitiFinali")
        return try SifaParser.tabella(html: r.text, vuotoMarker: "Non è presente nessun esito")
    }
}

nonisolated enum SifaError: LocalizedError {
    case esameNonTrovato
    var errorDescription: String? { "L'esame non compare più fra quelli del tuo corso su SIFA." }
}
