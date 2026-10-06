import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Glossario del corso di studio: termini tecnici, strutture, sostanze, test… che ricorrono nelle lezioni. Serve a
/// correggere le parole che la trascrizione storpia ("dopamila" → "dopamina").
nonisolated struct Glossario: Codable, Sendable, Equatable {
    var corso: String
    var termini: [String]
    var generatoIl: Date
    var modello: String
    /// Termini aggiunti a mano: restano quando il glossario si ricrea.
    var aggiunti: [String]? = nil
    /// true se i termini generati sono già passati da `GlossarioCorso.filtra` (i glossari creati con Qwen no).
    var filtrato: Bool? = nil
    /// Parole proposte dal modello in una lezione ma sconosciute al dizionario e assenti dalla trascrizione: entrano
    /// nel glossario alla seconda lezione in cui ricompaiono (parola → lezioni).
    var candidati: [String: Int]? = nil
    /// Termini imparati dalle lezioni riassunte: restano quando il glossario si ricrea.
    var imparati: [String]? = nil
}

nonisolated enum GlossarioCorso {
    private static var cartella: URL {
        URL.applicationSupportDirectory.appending(path: "Glossari", directoryHint: .isDirectory)
    }

    private static func url(_ codiceCorso: String) -> URL {
        cartella.appending(path: "\(codiceCorso.filter { $0.isLetter || $0.isNumber }).json")
    }

    static func carica(_ codiceCorso: String) -> Glossario? {
        (try? Data(contentsOf: url(codiceCorso))).flatMap { try? JSONDecoder().decode(Glossario.self, from: $0) }
    }

    static func salva(_ g: Glossario, codiceCorso: String) {
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        try? JSONEncoder().encode(g).write(to: url(codiceCorso), options: .atomic)
    }

    static func elimina(_ codiceCorso: String) {
        try? FileManager.default.removeItem(at: url(codiceCorso))
    }

    static func eliminaTutti() {
        try? FileManager.default.removeItem(at: cartella)
    }

    // MARK: Generazione

    static let istruzioni = """
        Sei un docente universitario italiano esperto della materia. Elenca solo termini reali, che si trovano nei \
        manuali universitari, scritti con l'ortografia italiana corretta.
        """

    /// Tre richieste per insegnamento, una per tipo di termine: il modello sul telefono rende meglio su elenchi brevi
    /// e mirati, e con una sola richiesta per insegnamento il glossario restava piccolo (89 termini contro i circa
    /// 500, non filtrati, di Qwen). I tipi sono generici: il glossario serve a qualsiasi corso di laurea.
    static let categorie = [
        "concetti, teorie, leggi, principi, modelli e classificazioni",
        "strutture, componenti, sostanze, organi, istituti o oggetti di studio",
        "processi, fenomeni, disturbi, metodi, tecniche, test, scale e strumenti",
    ]

    static func richieste(corso: String, insegnamenti: [String]) -> [String] {
        let elenco = insegnamenti.isEmpty ? [corso] : insegnamenti
        return elenco.flatMap { ins in
            categorie.map { categoria in
                """
                Corso di laurea: \(corso).
                Insegnamento: \(ins).
                Elenca le parole tecniche di questo insegnamento che un docente pronuncia spesso a lezione e che una \
                persona comune non conosce, solo di questo tipo: \(categoria). Preferisci parole singole (come \
                «assone», «mielina», «usucapione», «elasticità») e solo poche espressioni tipiche (come «nodi di \
                Ranvier»). Niente espressioni generiche, niente nomi di persona da soli. In minuscolo i termini comuni.
                """
            }
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct TerminiInsegnamento {
        @Guide(description: "Parole tecniche specifiche della materia (meglio se singole), senza spiegazioni né ripetizioni", .minimumCount(15), .maximumCount(40))
        let termini: [String]
    }
    #endif

    enum Errore: LocalizedError {
        case nonDisponibile
        var errorDescription: String? { "Apple Intelligence non è disponibile: attivala in Impostazioni › Apple Intelligence e Siri." }
    }

    /// Termini generati con Apple Intelligence (sul telefono o online), una richiesta guidata per insegnamento: la
    /// risposta è già un elenco, senza testo da ripulire. Temperatura bassa: termini noti, non inventati.
    @concurrent
    static func genera(con motore: MotoreRiassunto, corso: String, insegnamenti: [String],
                       progresso: @escaping @Sendable (Double) -> Void) async throws -> [[String]] {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { throw Errore.nonDisponibile }
        let richieste = richieste(corso: corso, insegnamenti: insegnamenti)
        var elenchi: [[String]] = []
        for (i, r) in richieste.enumerated() {
            try Task.checkCancellation()
            progresso(Double(i) / Double(richieste.count))
            let sessione: LanguageModelSession
            if motore == .cloud, #available(iOS 27.0, *) {
                sessione = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: istruzioni)
            } else {
                sessione = LanguageModelSession(instructions: istruzioni)
            }
            do {
                let risposta = try await AppleIntelligence.conRiprova {
                    try await sessione.respond(to: r, generating: TerminiInsegnamento.self,
                                               options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 800))
                }
                elenchi.append(risposta.content.termini
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                    .filter { t in (1...4).contains(t.split(separator: " ").count) && (3...50).contains(t.count) })
            } catch where AppleIntelligence.violaProtezioni(error) || AppleIntelligence.superaContesto(error) {
                // Un insegnamento rifiutato dalle protezioni o con una risposta troppo lunga non ferma gli altri.
                continue
            }
        }
        progresso(1)
        return elenchi
        #else
        throw Errore.nonDisponibile
        #endif
    }

    private static let paroleVuote: Set<String> = [
        "di", "del", "dello", "della", "dei", "degli", "delle", "e", "ed", "a", "al", "allo", "alla", "ai", "agli",
        "alle", "da", "dal", "dalla", "in", "nel", "nella", "nei", "per", "con", "su", "sul", "sulla", "il", "lo", "la",
        "i", "gli", "le", "un", "uno", "una", "tra", "fra", "of", "the", "and", "l", "d",
    ]

    /// Toglie dai termini generati quelli che non servono o fanno danni (su un glossario creato con Qwen c'erano
    /// parole inventate e nomi di persona):
    /// - parole in minuscolo sconosciute ai dizionari italiano e inglese, salvo se `confermata`: il correttore
    ///   ortografico non conosce molti termini tecnici veri ("neurotrasmettitori", "sinaptica"), che si riconoscono
    ///   perché compaiono nelle trascrizioni o il modello li propone per più insegnamenti; le parole inventate
    ///   ("fenotiropo") di solito compaiono una volta sola;
    /// - termini fatti solo di parole con la maiuscola sconosciute: nomi di persona ("Mario Rossi"); restano gli
    ///   eponimi dentro un termine ("nodi di Ranvier", "area di Broca");
    /// - sigle (non servono alla correzione, che guarda parole di almeno 6 lettere).
    /// Le parole comuni scritte con la maiuscola tornano in minuscolo ("Dopamina" → "dopamina").
    static func filtra(_ termini: [String], valida: (String) -> Bool, validaInglese: (String) -> Bool,
                       confermata: (String) -> Bool = { _ in false }) -> [String] {
        termini.compactMap { termine in
            let parole = termine.split { $0 == " " || $0 == "-" || $0 == "'" || $0 == "’" }.map(String.init)
            let contenuto = parole.filter { !paroleVuote.contains($0.lowercased()) }
            guard !contenuto.isEmpty, contenuto.allSatisfy({ $0.allSatisfy(\.isLetter) }) else { return nil }
            if contenuto.allSatisfy({ $0.count > 1 && $0 == $0.uppercased() }) { return nil }
            func nota(_ p: String) -> Bool { let m = p.lowercased(); return valida(m) || validaInglese(m) }
            let minuscole = contenuto.filter { $0.first?.isLowercase == true }
            let maiuscole = contenuto.filter { $0.first?.isUppercase == true }
            guard minuscole.allSatisfy({ nota($0) || confermata($0.lowercased()) }) else { return nil }
            if minuscole.isEmpty, !maiuscole.allSatisfy(nota) { return nil }
            // Maiuscola solo per i nomi propri (parole che il dizionario non conosce in minuscolo).
            var risultato = termine
            for p in maiuscole where nota(p) {
                risultato = risultato.replacingOccurrences(of: p, with: p.lowercased())
            }
            return risultato
        }
    }

    /// Parole proposte per almeno due insegnamenti diversi (conferma per i termini sconosciuti al dizionario).
    static func paroleRipetute(_ elenchi: [[String]]) -> Set<String> {
        var conteggi: [String: Int] = [:]
        for elenco in elenchi {
            let parole = Set(elenco.flatMap { $0.lowercased().split { !$0.isLetter }.map(String.init) })
            for p in parole { conteggi[p, default: 0] += 1 }
        }
        return Set(conteggi.filter { $0.value >= 2 }.keys)
    }

    /// I termini del glossario che compaiono in un pezzo di trascrizione, anche storpiati (una o due lettere di
    /// differenza): si passano al modello del riassunto perché li scriva nella forma giusta. Prima quelli storpiati,
    /// che sono quelli che servono davvero.
    static func pertinenti(_ glossario: [String], a testo: String, massimo: Int) -> [String] {
        let parole = Set(testo.lowercased().split { !$0.isLetter }.lazy.filter { $0.count >= 5 }.map(String.init))
        let perLunghezza = Dictionary(grouping: parole) { $0.count }
        var esatti: [String] = []
        var storpiati: [String] = []
        for termine in glossario {
            let chiavi = termine.lowercased().split { !$0.isLetter }.filter { $0.count >= 5 }.map(String.init)
            guard !chiavi.isEmpty else { continue }
            if chiavi.contains(where: parole.contains) { esatti.append(termine); continue }
            let vicino = chiavi.contains { k in
                let soglia = k.count >= 10 ? 2 : 1
                return (k.count - soglia...k.count + soglia).contains { n in
                    perLunghezza[n]?.contains { CorrettoreTermini.distanza($0, k) <= soglia } ?? false
                }
            }
            if vicino { storpiati.append(termine) }
        }
        return Array((storpiati + esatti).prefix(massimo))
    }

    /// Riga del prompt con i termini del corso (vuota se non ce ne sono).
    static func rigaPrompt(_ termini: [String]) -> String {
        termini.isEmpty ? "" : "Termini del corso, con l'ortografia corretta (se nel testo compaiono storpiati, scrivili così): \(termini.joined(separator: ", ")).\n"
    }

    static func unisci(_ elenchi: [String]...) -> [String] {
        var visti = Set<String>()
        return elenchi.flatMap { $0 }.filter { visti.insert($0.lowercased()).inserted }.sorted { $0.localizedCompare($1) == .orderedAscending }
    }
}

/// Correzione delle parole storpiate dalla trascrizione con il glossario del corso.
/// Una parola si sostituisce solo se:
/// - il correttore ortografico italiano la considera sbagliata (le parole italiane corrette non si toccano mai:
///   "domina" resta "domina" anche se il glossario ha "dopamina");
/// - non è una parola inglese valida (citazioni, termini in inglese);
/// - è lunga almeno 6 lettere e un solo termine del glossario le è vicinissimo: 1 lettera di differenza, 2 dalle
///   10 lettere in su (prove su due lezioni reali: con soglie più larghe "endogrine" diventava "endorfine");
/// - la differenza non è solo di forma (singolare/plurale, desinenza, derivati): "neurotrasmettitore" non diventa
///   "neurotrasmettitori", "recettorici" non diventa "recettori", "neuropsicologia" non diventa
///   "neuropsicologica". Se il termine ha un'altra desinenza, si tiene quella della parola trascritta
///   ("decettore" → "recettore" anche se il glossario ha "recettori");
/// - il correttore ortografico non propone una parola più vicina del termine: "pertebrale" (vertebrale) non
///   diventa "cerebrale", "inervazione" (innervazione) non diventa "interazione".
/// - i termini si scrivono in minuscolo, salvo i nomi propri (maiuscola e assenti dal dizionario: "Ranvier").
nonisolated enum CorrettoreTermini {
    struct Esito: Sendable {
        let testo: String
        let correzioni: [String: String]   // parola trovata → termine
    }

    static func correggi(_ testo: String, glossario: [String], valida: (String) -> Bool,
                         validaInglese: (String) -> Bool = { _ in false },
                         suggerimenti: (String) -> [String] = { _ in [] }) -> Esito {
        // Parole del glossario (anche quelle dentro le espressioni), in minuscolo → forma da scrivere.
        // Se il modello ha scritto tutto con la maiuscola, la maiuscola non distingue i nomi propri.
        let maiuscoleAffidabili = glossario.filter { $0.first?.isLowercase == true }.count * 5 >= glossario.count
        var forme: [String: String] = [:]
        for t in glossario {
            for p in t.split(separator: " ") where p.count >= 6 && p.allSatisfy(\.isLetter) {
                let minuscola = p.lowercased()
                let nomeProprio = p.first?.isUppercase == true && maiuscoleAffidabili && !valida(minuscola)
                forme[minuscola] = forme[minuscola] ?? (nomeProprio ? String(p) : minuscola)
            }
        }
        let perLunghezza = Dictionary(grouping: forme.keys) { $0.count }
        var cache: [String: String?] = [:]
        var correzioni: [String: String] = [:]
        var uscita = ""
        uscita.reserveCapacity(testo.count)
        var parola = ""
        func chiudi() {
            defer { parola = "" }
            guard parola.count >= 6 else { uscita += parola; return }
            let minuscola = parola.lowercased()
            let sostituto: String?
            if let c = cache[minuscola] {
                sostituto = c
            } else {
                var trovato: String?
                if forme[minuscola] == nil, !valida(minuscola), !validaInglese(minuscola) {
                    let soglia = minuscola.count >= 10 ? 2 : 1
                    let candidati = (minuscola.count - soglia...minuscola.count + soglia)
                        .flatMap { perLunghezza[$0] ?? [] }
                        .map { ($0, distanza(minuscola, $0)) }
                        .filter { $0.1 <= soglia }
                    let migliore = candidati.map(\.1).min()
                    let migliori = candidati.filter { $0.1 == migliore }
                    if migliori.count == 1, let forma = forme[migliori[0].0], let migliore,
                       !suggerimenti(minuscola).contains(where: { distanza(minuscola, $0.lowercased()) < migliore }) {
                        trovato = adatta(forma, a: minuscola)
                    }
                }
                cache[minuscola] = trovato
                sostituto = trovato
            }
            guard let sostituto else { uscita += parola; return }
            let finale = parola.first?.isUppercase == true && sostituto.first?.isLowercase == true
                ? sostituto.prefix(1).uppercased() + sostituto.dropFirst() : sostituto
            correzioni[parola] = finale
            uscita += finale
        }
        for c in testo {
            if c.isLetter { parola.append(c) } else { chiudi(); uscita.append(c) }
        }
        chiudi()
        return Esito(testo: uscita, correzioni: correzioni)
    }

    private static let vocali: Set<Character> = ["a", "e", "i", "o", "u"]
    private static let desinenze = ["iche", "ici", "ica", "ico", "ia", "ie", "a", "e", "i", "o"]

    /// La parola senza la desinenza più lunga fra quelle comuni: "neuropsicologia" e "neuropsicologica" hanno la
    /// stessa radice, "dopamila" e "dopamina" no.
    private static func radice(_ parola: String) -> Substring {
        for d in desinenze where parola.hasSuffix(d) && parola.count - d.count >= 4 { return parola.dropLast(d.count) }
        return Substring(parola)
    }

    /// Il termine con la desinenza della parola trascritta; nil se le due parole differiscono solo per la forma.
    static func adatta(_ termine: String, a parola: String) -> String? {
        let t = termine.lowercased()
        if t.hasPrefix(parola) || parola.hasPrefix(t) || t.hasSuffix(parola) || parola.hasSuffix(t) { return nil }
        if radice(t) == radice(parola) { return nil }
        guard let ft = t.last, let fp = parola.last, vocali.contains(ft), vocali.contains(fp) else { return termine }
        if t.dropLast() == parola.dropLast() { return nil }
        return ft == fp ? termine : String(termine.dropLast()) + String(fp)
    }

    /// Distanza di Damerau-Levenshtein (con scambio di lettere vicine).
    static func distanza(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let costo = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + costo)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
