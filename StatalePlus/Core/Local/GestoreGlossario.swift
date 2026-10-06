import Foundation
import Observation
import UIKit

/// Glossario del corso dello studente: creazione con Apple Intelligence (online se disponibile, altrimenti sul
/// telefono), modifiche a mano e correzione delle trascrizioni. Il codice del corso arriva da `AppModel` (`codiceCorso`).
@Observable
final class GestoreGlossario {
    enum Stato: Equatable { case inattivo, creazione(Double) }

    private(set) var glossario: Glossario?
    private(set) var stato: Stato = .inattivo
    private(set) var errore: String?
    @ObservationIgnored var codiceCorso: () -> String? = { nil }
    @ObservationIgnored private var caricatoPer: String?
    @ObservationIgnored private var compito: Task<Void, Never>?

    /// Glossario del corso attuale (dal disco se non ancora letto, senza modificare lo stato osservato).
    var attuale: Glossario? {
        guard let codice = codiceCorso() else { return nil }
        return caricatoPer == codice ? glossario : GlossarioCorso.carica(codice)
    }

    /// Legge il glossario del corso attuale (all'apertura della schermata). Un glossario creato prima del filtro dei
    /// termini (con Qwen) si ripulisce subito da parole inventate e nomi di persona, tenendo quelli aggiunti a mano.
    func ricarica() {
        guard let codice = codiceCorso(), caricatoPer != codice else { return }
        caricatoPer = codice
        glossario = GlossarioCorso.carica(codice)
        if var g = glossario, g.filtrato != true {
            let aggiunti = g.aggiunti ?? []
            let generati = g.termini.filter { !aggiunti.contains($0) }
            g.termini = GlossarioCorso.unisci(aggiunti, filtra(generati))
            g.filtrato = true
            GlossarioCorso.salva(g, codiceCorso: codice)
            glossario = g
        }
    }

    /// Modello con cui si crea il glossario: Apple Intelligence online se disponibile, altrimenti sul telefono.
    var motore: MotoreRiassunto? {
        if NuvolaApple.stato == .disponibile { return .cloud }
        return AppleIntelligence.stato == .disponibile ? .apple : nil
    }

    /// `paroleTrascritte`: parole (in minuscolo) delle trascrizioni già fatte, per confermare i termini tecnici che
    /// il dizionario non conosce.
    func crea(corso: String, insegnamenti: [InsegnamentoAgenda], paroleTrascritte: Set<String>) {
        guard compito == nil, let codice = codiceCorso() else { return }
        guard let motore else { errore = GlossarioCorso.Errore.nonDisponibile.errorDescription; return }
        errore = nil
        stato = .creazione(0)
        let nomi = insegnamenti.map(\.nome)
        let aggiunti = attuale?.aggiunti ?? []
        let imparati = attuale?.imparati ?? []
        let candidati = attuale?.candidati
        compito = Task {
            do {
                let aggiorna: @Sendable (Double) -> Void = { p in Task { @MainActor in self.stato = .creazione(p) } }
                let elenchi = try await EsecuzioneEstesa.esegui(titolo: "Glossario del corso", sottotitolo: "\(nomi.count) insegnamenti") { sistema in
                    try await GlossarioCorso.genera(con: motore, corso: corso, insegnamenti: nomi) { p in sistema(p); aggiorna(p) }
                }
                let ripetute = GlossarioCorso.paroleRipetute(elenchi)
                let generati = filtra(elenchi.flatMap { $0 }) { ripetute.contains($0) || paroleTrascritte.contains($0) }
                let g = Glossario(corso: corso, termini: GlossarioCorso.unisci(aggiunti, imparati, generati),
                                  generatoIl: .now, modello: motore.nome, aggiunti: aggiunti, filtrato: true,
                                  candidati: candidati, imparati: imparati)
                GlossarioCorso.salva(g, codiceCorso: codice)
                glossario = g
                caricatoPer = codice
            } catch is CancellationError {
            } catch {
                errore = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            stato = .inattivo
            compito = nil
        }
    }

    private func filtra(_ termini: [String], confermata: (String) -> Bool = { _ in false }) -> [String] {
        GlossarioCorso.filtra(termini, valida: Dizionario.italiano.valida, validaInglese: Dizionario.inglese.valida,
                              confermata: confermata)
    }

    func annulla() { compito?.cancel() }

    /// Termini tecnici riconosciuti dal modello in una lezione riassunta (`Riassunto.termini`, nella forma corretta):
    /// il glossario cresce con le lezioni. Passano dallo stesso filtro della creazione; una parola sconosciuta al
    /// dizionario entra solo quando il modello la propone in una seconda lezione. Comparire nella trascrizione non
    /// basta: nella prova sulla lezione di neuroanatomia il modello copiava anche errori della trascrizione
    /// ("brassia" per "aprassia"). Restituisce quanti termini sono stati aggiunti.
    @discardableResult
    func impara(_ termini: [String], trascrizione: String) -> Int {
        ricarica()
        guard let codice = codiceCorso(), !termini.isEmpty else { return 0 }
        var g = glossario ?? Glossario(corso: "", termini: [], generatoIl: .now, modello: "dalle lezioni", filtrato: true)
        let presenti = Set(g.termini.map { $0.lowercased() })
        let nuovi = GlossarioCorso.unisci(termini.map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) })
            .filter { t in !presenti.contains(t.lowercased()) && (1...4).contains(t.split(separator: " ").count) && (3...50).contains(t.count) }
        guard !nuovi.isEmpty else { return 0 }
        var candidati = g.candidati ?? [:]
        var sconosciute = Set<String>()
        let accettati = filtra(nuovi) { p in
            if candidati[p, default: 0] >= 1 { return true }
            sconosciute.insert(p)
            return false
        }
        for p in sconosciute { candidati[p, default: 0] += 1 }
        for t in accettati { for p in t.lowercased().split(whereSeparator: { !$0.isLetter }) { candidati[String(p)] = nil } }
        g.candidati = candidati
        g.termini = GlossarioCorso.unisci(g.termini, accettati)
        g.imparati = GlossarioCorso.unisci(g.imparati ?? [], accettati)
        GlossarioCorso.salva(g, codiceCorso: codice)
        glossario = g
        return accettati.count
    }

    func aggiungi(_ termine: String) {
        let t = termine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let codice = codiceCorso() else { return }
        var g = attuale ?? Glossario(corso: "", termini: [], generatoIl: .now, modello: "a mano", filtrato: true)
        g.termini = GlossarioCorso.unisci(g.termini, [t])
        g.aggiunti = GlossarioCorso.unisci(g.aggiunti ?? [], [t])
        GlossarioCorso.salva(g, codiceCorso: codice)
        glossario = g
        caricatoPer = codice
    }

    func rimuovi(_ termini: [String]) {
        guard var g = attuale, let codice = codiceCorso() else { return }
        let via = Set(termini)
        g.termini.removeAll { via.contains($0) }
        g.aggiunti?.removeAll { via.contains($0) }
        g.imparati?.removeAll { via.contains($0) }
        GlossarioCorso.salva(g, codiceCorso: codice)
        glossario = g
    }

    func elimina() {
        guard let codice = codiceCorso() else { return }
        GlossarioCorso.elimina(codice)
        glossario = nil
        caricatoPer = codice
    }

    // MARK: Correzione

    /// Testo corretto con il glossario del corso (o quello originale se non c'è un glossario).
    func correggi(_ testo: String) -> CorrettoreTermini.Esito {
        ricarica()
        guard let termini = glossario?.termini, !termini.isEmpty else { return .init(testo: testo, correzioni: [:]) }
        return CorrettoreTermini.correggi(testo, glossario: termini, valida: Dizionario.italiano.valida,
                                          validaInglese: Dizionario.inglese.valida,
                                          suggerimenti: Dizionario.italiano.suggerimenti)
    }

    /// Applica il glossario alle trascrizioni già fatte. Restituisce (parole corrette, trascrizioni cambiate).
    func correggiTrascrizioni(in store: RecordingStore) -> (parole: Int, trascrizioni: Int) {
        var parole = 0, trascrizioni = 0
        for r in store.items {
            guard let testo = store.trascrizione(r.id) else { continue }
            let esito = correggi(testo)
            guard esito.testo != testo else { continue }
            store.salvaTrascrizione(r.id, esito.testo)
            parole += esito.correzioni.count
            trascrizioni += 1
        }
        return (parole, trascrizioni)
    }
}

/// Il correttore ortografico di iOS per una lingua, con i risultati ricordati per parola.
@MainActor
final class Dizionario {
    static let italiano = Dizionario(prefisso: "it")
    static let inglese = Dizionario(prefisso: "en")

    private let checker = UITextChecker()
    private let lingua: String?
    private var cache: [String: Bool] = [:]

    private init(prefisso: String) {
        lingua = UITextChecker.availableLanguages.first { $0.hasPrefix(prefisso) }
    }

    func valida(_ parola: String) -> Bool {
        guard let lingua else { return prefissoAssente }
        if let v = cache[parola] { return v }
        let ns = parola as NSString
        let v = checker.rangeOfMisspelledWord(in: parola, range: NSRange(location: 0, length: ns.length),
                                              startingAt: 0, wrap: false, language: lingua).location == NSNotFound
        cache[parola] = v
        return v
    }

    /// Parole simili proposte dal correttore ortografico per una parola sconosciuta.
    func suggerimenti(_ parola: String) -> [String] {
        guard let lingua else { return [] }
        let ns = parola as NSString
        return checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: parola, language: lingua) ?? []
    }

    /// Senza dizionario italiano non si corregge nulla (ogni parola risulta valida); senza inglese si ignora il filtro.
    private var prefissoAssente: Bool { self === Dizionario.italiano }
}
