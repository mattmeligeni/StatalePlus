import Foundation

/// Un punto della trascrizione legato all'audio, come un sottotitolo: l'istante `t` (secondi) e le prime parole che
/// iniziano lì, normalizzate (minuscole, solo lettere e cifre).
nonisolated struct Ancora: Codable, Sendable, Equatable {
    let t: Double
    let parole: [String]
}

/// Testo di una trascrizione con le sue àncore (vuote se il motore non dà i tempi).
nonisolated struct TestoTrascritto: Sendable {
    var testo: String
    var ancore: [Ancora]
}

/// Mappa tempo → testo delle trascrizioni, per evidenziare durante l'ascolto il punto che si sta ascoltando.
/// Durante la trascrizione si salva un'àncora circa ogni 3 secondi (`<id>.tempi.json`, poche decine di KB anche per
/// lezioni di ore); nella vista le àncore si ritrovano nel testo cercandone le parole (`MappaTesto`), così la mappa
/// regge alle correzioni del glossario e alle modifiche fatte a mano. Fra un'àncora e l'altra il punto si interpola.
nonisolated enum TempiTrascrizione {
    static let intervallo: Double = 3
    static let paroleAncora = 4

    static func normalizza<S: StringProtocol>(_ parola: S) -> String {
        String(parola.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func parole(_ testo: String) -> [String] {
        testo.split(whereSeparator: { $0.isWhitespace }).map(normalizza).filter { !$0.isEmpty }
    }

    /// Àncore da parole con il loro istante: una ogni `intervallo` secondi, con le parole che seguono.
    static func ancore(da parole: [(t: Double, parola: String)]) -> [Ancora] {
        var ancore: [Ancora] = []
        var ultima = -Double.infinity
        for (i, p) in parole.enumerated() where p.t >= ultima + intervallo {
            let seguenti = parole[i..<min(i + paroleAncora, parole.count)].map(\.parola)
            ancore.append(Ancora(t: p.t, parole: seguenti))
            ultima = p.t
        }
        return ancore
    }
}

/// Le àncore ritrovate in un testo: dal tempo alla posizione nel testo e viceversa.
nonisolated struct MappaTesto: Sendable {
    /// Posizione (in caratteri) dell'inizio di ogni parola del testo.
    private let posizioni: [Int]
    /// Punti noti: istante e indice di parola, in ordine.
    private let punti: [(t: Double, parola: Int)]
    let lunghezza: Int
    /// true se le posizioni vengono dalle àncore; false se sono stimate in proporzione alla durata.
    let precisa: Bool

    init(testo: String, ancore: [Ancora], durata: Double) {
        var posizioni: [Int] = []
        var normalizzate: [String] = []
        var offset = 0
        var inParola = false
        var corrente = ""
        for c in testo {
            if c.isWhitespace {
                if inParola { normalizzate.append(TempiTrascrizione.normalizza(corrente)); corrente = ""; inParola = false }
            } else {
                if !inParola { posizioni.append(offset); inParola = true }
                corrente.append(c)
            }
            offset += 1
        }
        if inParola { normalizzate.append(TempiTrascrizione.normalizza(corrente)) }
        self.posizioni = posizioni
        lunghezza = offset

        // Ogni àncora si cerca poco dopo la precedente: bastano 3 parole su 4 uguali (correzioni, modifiche).
        var punti: [(t: Double, parola: Int)] = []
        var cursore = 0
        let n = normalizzate.count
        for a in ancore where !a.parole.isEmpty {
            let richieste = max(1, min(a.parole.count, 3))
            var trovata: Int?
            var w = cursore
            while w < min(n, cursore + 800) {
                var uguali = 0
                for (k, p) in a.parole.enumerated() where w + k < n && normalizzate[w + k] == p { uguali += 1 }
                if uguali >= richieste { trovata = w; break }
                w += 1
            }
            if let trovata, punti.last.map({ a.t >= $0.t }) ?? true {
                punti.append((a.t, trovata))
                cursore = trovata + 1
            }
        }
        precisa = punti.count >= 2
        if !precisa, n > 0 {
            punti = [(0, 0), (max(durata, 1), n - 1)]
        } else if let primo = punti.first, primo.parola > 0 || primo.t > 0 {
            punti.insert((0, 0), at: 0)
        }
        self.punti = punti
    }

    /// Posizione nel testo della parola che si sente all'istante `t`.
    func posizione(al t: Double) -> Int? {
        guard !posizioni.isEmpty, !punti.isEmpty else { return nil }
        let i = punti.lastIndex { $0.t <= t } ?? 0
        let a = punti[i]
        let indice: Double
        if i + 1 < punti.count {
            let b = punti[i + 1]
            let f = b.t > a.t ? min(max((t - a.t) / (b.t - a.t), 0), 1) : 0
            indice = Double(a.parola) + f * Double(b.parola - a.parola)
        } else {
            indice = Double(a.parola)
        }
        return posizioni[min(max(Int(indice.rounded(.down)), 0), posizioni.count - 1)]
    }

    /// Istante in cui si sente il testo alla posizione `offset` (per toccare un paragrafo e ascoltarlo).
    func tempo(per offset: Int) -> Double? {
        guard !posizioni.isEmpty, punti.count >= 2 else { return nil }
        let parola = (posizioni.lastIndex { $0 <= offset } ?? 0)
        let i = punti.lastIndex { $0.parola <= parola } ?? 0
        let a = punti[i]
        guard i + 1 < punti.count else { return a.t }
        let b = punti[i + 1]
        let f = b.parola > a.parola ? Double(parola - a.parola) / Double(b.parola - a.parola) : 0
        return a.t + f * (b.t - a.t)
    }
}
