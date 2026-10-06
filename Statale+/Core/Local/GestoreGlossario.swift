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
        compito = Task {
            do {
                let aggiorna: @Sendable (Double) -> Void = { p in Task { @MainActor in self.stato = .creazione(p) } }
                let elenchi = try await EsecuzioneEstesa.esegui(titolo: "Glossario del corso", sottotitolo: "\(nomi.count) insegnamenti") { sistema in
                    try await GlossarioCorso.genera(con: motore, corso: corso, insegnamenti: nomi) { p in sistema(p); aggiorna(p) }
                }
                let ripetute = GlossarioCorso.paroleRipetute(elenchi)
                let generati = filtra(elenchi.flatMap { $0 }) { ripetute.contains($0) || paroleTrascritte.contains($0) }
                let g = Glossario(corso: corso, termini: GlossarioCorso.unisci(aggiunti, generati),
                                  generatoIl: .now, modello: motore.nome, aggiunti: aggiunti, filtrato: true)
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
