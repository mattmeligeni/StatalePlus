import Foundation

/// Tipi di decodifica tolleranti, ognuno motivato da un'anomalia osservata nei dati reali.

/// Valore che arriva a volte come numero e a volte come stringa.
/// Fonte: `api mobili/orario/1corsi.json` — `$[].valore` è `0` (Int) nella prima voce, stringa nelle altre.
nonisolated struct StringOrInt: Codable, Hashable, Sendable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(d) }
        else { value = "" }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(value)
    }
}

/// Numero che può arrivare come Int, Double o stringa numerica.
/// Fonte: `rilevatore_presenze/frequentati.json` (`OreLimite: 1847.9999999999998`, `Frequentate: 240`).
nonisolated struct FlexibleDouble: Codable, Hashable, Sendable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self), let d = Double(s.replacingOccurrences(of: ",", with: ".")) { value = d }
        else { value = 0 }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(value)
    }
}

/// Dizionario serializzato da PHP: se vuoto arriva come `[]` invece di `{}`.
/// Verificato dal vivo il 29-09-2026: `test_call.php` con intervallo senza appelli risponde
/// `"Insegnamenti":[]`, mentre `api mobili/esami/2esami.json` lo ha come oggetto.
nonisolated struct PHPDictionary<Value: Decodable & Sendable>: Decodable, Sendable {
    let values: [String: Value]
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let dict = try? c.decode([String: Value].self) {
            values = dict
        } else if let arr = try? c.decode([Value].self) {
            values = Dictionary(uniqueKeysWithValues: arr.enumerated().map { (String($0.offset), $0.element) })
        } else {
            values = [:]
        }
    }
}

nonisolated extension KeyedDecodingContainer {
    func string(_ key: Key) -> String {
        (try? decodeIfPresent(StringOrInt.self, forKey: key))??.value ?? ""
    }
    /// "0"/"1" come stringa (EasyBadge `svolta`, `Presenza`; esami `event_Annullato`).
    func flag(_ key: Key) -> Bool {
        let s = string(key)
        return s == "1" || s.lowercased() == "true"
    }
    func double(_ key: Key) -> Double {
        (try? decodeIfPresent(FlexibleDouble.self, forKey: key))??.value ?? 0
    }
}
