import Foundation

/// Le risposte EasyBadge sono indicizzate per matricola minuscola (chiave dinamica).
nonisolated enum EasyBadgeParser {
    /// frequentati.json: `{ "<matr>": { "<nome corso>": [Frequenza] } }`
    static func frequenze(_ data: Data) throws -> [Frequenza] {
        let outer = try JSONDecoder().decode(PHPDictionary<PHPDictionary<[Frequenza]>>.self, from: data)
        return outer.values.values
            .flatMap { $0.values.values.flatMap { $0 } }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    /// timbrature.json: `{ "<matr>": [SlotLezione] }`
    static func slot(_ data: Data) throws -> [SlotLezione] {
        let outer = try JSONDecoder().decode(PHPDictionary<[SlotLezione]>.self, from: data)
        return outer.values.values.flatMap { $0 }.sorted { $0.inizio < $1.inizio }
    }

    static func esitoTimbratura(_ data: Data) throws -> TimbraturaResult {
        try JSONDecoder().decode(TimbraturaResult.self, from: data)
    }
}
