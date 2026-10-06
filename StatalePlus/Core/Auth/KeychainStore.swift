import Foundation
import Security

/// Credenziali universitarie: unico segreto dell'app, SOLO in Keychain.
nonisolated struct Credentials: Codable, Sendable {
    let email: String      // "nome.cognome@studenti.unimi.it" (username CAS)
    let password: String

    /// Ariel vuole la sola parte locale in `tbLogin` e il dominio in `ddlType`.
    var localPart: String { email.split(separator: "@").first.map(String.init) ?? email }
    var domain: String { "@" + Self.dominioStudenti }

    // MARK: Validazione

    /// Accesso riservato agli studenti immatricolati: solo indirizzi @studenti.unimi.it.
    static let dominioStudenti = "studenti.unimi.it"

    enum EmailError: LocalizedError, Equatable {
        case vuota
        case dominioNonAmmesso(String)
        case formatoNonValido

        var errorDescription: String? {
            switch self {
            case .vuota: "Inserisci il tuo indirizzo email di Ateneo."
            case .dominioNonAmmesso(let d): "Il dominio @\(d) non è ammesso: l'accesso è riservato agli indirizzi @\(Credentials.dominioStudenti)."
            case .formatoNonValido: "Indirizzo non valido: usa il formato nome.cognome@\(Credentials.dominioStudenti)."
            }
        }
    }

    /// "nome.cognome" → "nome.cognome@studenti.unimi.it"; "nome.cognome@studenti.unimi.it" invariato;
    /// qualsiasi altro dominio → errore.
    static func normalizzaEmail(_ input: String) -> Result<String, EmailError> {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return .failure(.vuota) }
        if s == Demo.email { return .success(Demo.email) }
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return .failure(.formatoNonValido) }
        let local = String(parts[0])
        if parts.count == 2 {
            let dominio = String(parts[1])
            guard !dominio.isEmpty else { return .failure(.formatoNonValido) }
            guard dominio == dominioStudenti else { return .failure(.dominioNonAmmesso(dominio)) }
        }
        guard local.range(of: #"^[a-z0-9]+([._-][a-z0-9]+)*$"#, options: .regularExpression) != nil else {
            return .failure(.formatoNonValido)
        }
        return .success("\(local)@\(dominioStudenti)")
    }
}

nonisolated enum KeychainStore {
    private static let service = "com.mattiameligeni.statale.credentials"
    private static let account = "unimi"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ c: Credentials) throws {
        let data = try JSONEncoder().encode(c)
        SecItemDelete(baseQuery as CFDictionary)
        var q = baseQuery
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func load() -> Credentials? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
