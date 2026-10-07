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

    /// Motore di trascrizione scelto in Impostazioni (predefinito: Apple).
    static var motoreTrascrizione: MotoreTrascrizione {
        get { defaults.string(forKey: "motoreTrascrizione").flatMap(MotoreTrascrizione.init(rawValue:)) ?? .apple }
        set { defaults.set(newValue.rawValue, forKey: "motoreTrascrizione") }
    }

    /// Motore dei riassunti (Altro › IA). Predefinito: Apple Intelligence online, che si usa solo se disponibile
    /// (altrimenti quella sul telefono). Scaricato Qwen, diventa lui il motore scelto (`MotoreRiassunto.disponibile`).
    static var motoreRiassunto: MotoreRiassunto {
        get { defaults.string(forKey: "motoreRiassunto").flatMap(MotoreRiassunto.init(rawValue:)) ?? .cloud }
        set { defaults.set(newValue.rawValue, forKey: "motoreRiassunto") }
    }

    /// Dopo ogni registrazione: trascrizione e riassunto partono da soli.
    static var elaborazioneAutomatica: Bool {
        get { defaults.object(forKey: "elaborazioneAutomatica") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "elaborazioneAutomatica") }
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

    /// Modifiche locali alle lezioni (id lezione → modifica).
    static var modificheLezioni: [String: ModificaLezione] {
        get { defaults.data(forKey: "modificheLezioni").flatMap { try? JSONDecoder().decode([String: ModificaLezione].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "modificheLezioni") }
    }

    /// Avvisi «Non ti convince? Prova il modello più preciso» sotto trascrizioni e riassunti fatti con i modelli di
    /// base: chiusi dall'utente con «Non mostrare più».
    static let chiaveAvvisoTrascrizione = "avvisoModelloTrascrizioneNascosto"
    static let chiaveAvvisoRiassunto = "avvisoModelloRiassuntoNascosto"

    /// La presentazione delle funzioni (dopo il primo accesso) è già stata vista.
    static var presentazioneVista: Bool {
        get { defaults.bool(forKey: "presentazioneVista") }
        set { defaults.set(newValue, forKey: "presentazioneVista") }
    }

    static func azzera() {
        ["sogliaFrequenzaManuale", "obbligoFrequenza", "obbligoFrequenzaChiave", "avvisiLetti", "modificheLezioni",
         "presentazioneVista", chiaveAvvisoTrascrizione, chiaveAvvisoRiassunto]
            .forEach(defaults.removeObject(forKey:))
    }
}
