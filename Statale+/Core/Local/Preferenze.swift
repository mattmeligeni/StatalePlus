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

    /// Miglioramento automatico dell'audio dopo ogni registrazione (predefinito: attivo).
    static var miglioraAudio: Bool {
        get { defaults.object(forKey: "miglioraAudio") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "miglioraAudio") }
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

    /// Discussioni dei forum Ariel lette nell'app: id → istante dell'ultima lettura (secondi dal 1970).
    static var avvisiLetti: [String: Double] {
        get { defaults.dictionary(forKey: "avvisiLetti") as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: "avvisiLetti") }
    }

    static func azzera() {
        ["sogliaFrequenzaManuale", "obbligoFrequenza", "obbligoFrequenzaChiave", "avvisiLetti"].forEach(defaults.removeObject(forKey:))
    }
}
