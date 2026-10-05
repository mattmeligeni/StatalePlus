import Foundation
import Observation
import UIKit

/// Glossario del corso dello studente: creazione con Qwen (o Apple Intelligence), modifiche a mano e correzione
/// delle trascrizioni. Il codice del corso arriva da `AppModel` (`codiceCorso`).
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

    /// Legge il glossario del corso attuale (all'apertura della schermata).
    func ricarica() {
        guard let codice = codiceCorso(), caricatoPer != codice else { return }
        caricatoPer = codice
        glossario = GlossarioCorso.carica(codice)
    }

    /// Modello con cui si crea il glossario: Apple Intelligence online se autorizzata, poi Qwen se scaricato, poi
    /// Apple Intelligence sul telefono.
    var motore: MotoreRiassunto? {
        if NuvolaApple.stato == .disponibile { return .cloud }
        if QwenLocale.installato, QwenLocale.supportato { return .qwen }
        return AppleIntelligence.stato == .disponibile ? .apple : nil
    }

    func crea(corso: String, insegnamenti: [InsegnamentoAgenda]) {
        guard compito == nil, let codice = codiceCorso() else { return }
        errore = nil
        stato = .creazione(0)
        let motore = motore
        let nomi = insegnamenti.map(\.nome)
        let base = GlossarioCorso.terminiDiBase(insegnamenti: nomi, docenti: insegnamenti.map(\.docente))
        let manuali = attuale?.termini ?? []
        compito = Task {
            do {
                var generati: [String] = []
                if let motore {
                    let richieste = GlossarioCorso.richieste(corso: corso, insegnamenti: nomi)
                    let aggiorna: @Sendable (Double) -> Void = { p in Task { @MainActor in self.stato = .creazione(p) } }
                    let risposte = try await EsecuzioneEstesa.esegui(titolo: "Glossario del corso", sottotitolo: "\(nomi.count) insegnamenti",
                                                                     gpu: motore == .qwen) { sistema in
                        let progresso: @Sendable (Double) -> Void = { p in sistema(p); aggiorna(p) }
                        return switch motore {
                        case .qwen: try await QwenLocale.rispondi(richieste, istruzioni: GlossarioCorso.istruzioni, massimo: 900, progresso: progresso)
                        case .apple: try await AppleIntelligence.rispondi(richieste, istruzioni: GlossarioCorso.istruzioni, progresso: progresso)
                        case .cloud: try await NuvolaApple.rispondi(richieste, istruzioni: GlossarioCorso.istruzioni, progresso: progresso)
                        }
                    }
                    generati = risposte.flatMap(GlossarioCorso.termini(da:))
                }
                let g = Glossario(corso: corso, termini: GlossarioCorso.unisci(manuali, base, generati),
                                  generatoIl: .now, modello: motore?.nome ?? "solo nomi degli insegnamenti")
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

    func annulla() { compito?.cancel() }

    func aggiungi(_ termine: String) {
        let t = termine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let codice = codiceCorso() else { return }
        var g = attuale ?? Glossario(corso: "", termini: [], generatoIl: .now, modello: "a mano")
        g.termini = GlossarioCorso.unisci(g.termini, [t])
        GlossarioCorso.salva(g, codiceCorso: codice)
        glossario = g
        caricatoPer = codice
    }

    func rimuovi(_ termini: [String]) {
        guard var g = attuale, let codice = codiceCorso() else { return }
        let via = Set(termini)
        g.termini.removeAll { via.contains($0) }
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
        guard let termini = attuale?.termini, !termini.isEmpty else { return .init(testo: testo, correzioni: [:]) }
        return CorrettoreTermini.correggi(testo, glossario: termini, valida: Dizionario.italiano.valida,
                                          validaInglese: Dizionario.inglese.valida)
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

    /// Senza dizionario italiano non si corregge nulla (ogni parola risulta valida); senza inglese si ignora il filtro.
    private var prefissoAssente: Bool { self === Dizionario.italiano }
}
