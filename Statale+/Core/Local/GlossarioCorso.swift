import Foundation

/// Glossario del corso di studio: termini tecnici, autori, test, strutture… che ricorrono nelle lezioni. Serve a
/// correggere le parole che la trascrizione storpia ("dopamila" → "dopamina").
nonisolated struct Glossario: Codable, Sendable, Equatable {
    var corso: String
    var termini: [String]
    var generatoIl: Date
    var modello: String
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
        Sei un esperto di didattica universitaria italiana. Rispondi solo con un elenco di termini in italiano, uno per \
        riga, senza numeri, trattini, spiegazioni o frasi.
        """

    /// Una richiesta per insegnamento: i modelli locali hanno poco contesto e rendono meglio su elenchi brevi.
    static func richieste(corso: String, insegnamenti: [String]) -> [String] {
        let elenco = insegnamenti.isEmpty ? [corso] : insegnamenti
        return elenco.map { ins in
            """
            Corso di laurea: \(corso).
            Insegnamento: \(ins).
            Elenca 60 termini tecnici che compaiono spesso nelle lezioni di questo insegnamento: concetti, strutture, \
            sostanze, test, sindromi, metodi e cognomi di autori importanti. Scrivi ogni termine nella forma corretta, \
            con l'ortografia italiana: in minuscolo i termini comuni, con la maiuscola solo i nomi propri.
            """
        }
    }

    /// Termini puliti da un elenco generato: righe senza numerazione e punteggiatura, da 1 a 4 parole.
    static func termini(da testo: String) -> [String] {
        testo.split(whereSeparator: \.isNewline).compactMap { riga -> String? in
            var t = riga.trimmingCharacters(in: .whitespaces)
            t = t.replacingOccurrences(of: #"^(\d+[.)]|[-*•–])\s*"#, with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
            t = t.components(separatedBy: CharacterSet(charactersIn: ":(—")).first?.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) ?? ""
            let parole = t.split(separator: " ")
            guard (1...4).contains(parole.count), t.count >= 3, t.count <= 50,
                  t.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" }) else { return nil }
            return t
        }
    }

    /// Nomi degli insegnamenti e cognomi dei docenti: parole del corso sicure, senza bisogno di un modello.
    static func terminiDiBase(insegnamenti: [String], docenti: [String]) -> [String] {
        let parole = insegnamenti.flatMap { $0.split { !$0.isLetter && $0 != "'" } }.map(String.init).filter { $0.count >= 6 }
        let cognomi = docenti.flatMap { $0.split(separator: ",") }.compactMap { $0.split(separator: " ").last.map(String.init) }
        return parole + cognomi
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
///   "neurotrasmettitori", "recettorici" non diventa "recettori". Se il termine ha un'altra desinenza, si tiene
///   quella della parola trascritta ("decettore" → "recettore" anche se il glossario ha "recettori").
/// - i termini si scrivono in minuscolo, salvo i nomi propri (maiuscola e assenti dal dizionario: "Ranvier").
nonisolated enum CorrettoreTermini {
    struct Esito: Sendable {
        let testo: String
        let correzioni: [String: String]   // parola trovata → termine
    }

    static func correggi(_ testo: String, glossario: [String], valida: (String) -> Bool,
                         validaInglese: (String) -> Bool = { _ in false }) -> Esito {
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
                    if migliori.count == 1, let forma = forme[migliori[0].0] {
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

    /// Il termine con la desinenza della parola trascritta; nil se le due parole differiscono solo per la forma.
    static func adatta(_ termine: String, a parola: String) -> String? {
        let t = termine.lowercased()
        if t.hasPrefix(parola) || parola.hasPrefix(t) || t.hasSuffix(parola) || parola.hasSuffix(t) { return nil }
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
