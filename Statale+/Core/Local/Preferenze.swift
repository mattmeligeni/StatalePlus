import Foundation

/// Da dove viene la soglia di frequenza mostrata in Presenze.
nonisolated enum FonteSoglia: Sendable {
    case utente, manifesto, easyBadge

    var descrizione: String {
        switch self {
        case .utente: "scelta in Impostazioni"
        case .manifesto: "dal manifesto degli studi"
        case .easyBadge: "dal sistema presenze"
        }
    }
}

/// Piccole preferenze locali in `UserDefaults` (nessun dato sensibile).
nonisolated enum Preferenze {
    private static var defaults: UserDefaults { .standard }

    /// Soglia di frequenza scelta dall'utente in percentuale; 0 = automatica.
    static var sogliaManuale: Int {
        get { defaults.integer(forKey: "sogliaFrequenzaManuale") }
        set { defaults.set(newValue, forKey: "sogliaFrequenzaManuale") }
    }

    static var obbligoFrequenza: ObbligoFrequenza? {
        get { defaults.data(forKey: "obbligoFrequenza").flatMap { try? JSONDecoder().decode(ObbligoFrequenza.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "obbligoFrequenza") }
    }

    /// "DBD|1|2026": corso, anno di corso e anno accademico per cui è stato letto il manifesto.
    static var chiaveObbligoFrequenza: String? {
        get { defaults.string(forKey: "obbligoFrequenzaChiave") }
        set { defaults.set(newValue, forKey: "obbligoFrequenzaChiave") }
    }

    static func azzera() {
        ["sogliaFrequenzaManuale", "obbligoFrequenza", "obbligoFrequenzaChiave"].forEach(defaults.removeObject(forKey:))
    }
}
