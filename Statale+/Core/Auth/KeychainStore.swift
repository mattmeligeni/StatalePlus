import Foundation
import Security

/// Credenziali universitarie: unico segreto dell'app, SOLO in Keychain.
nonisolated struct Credentials: Codable, Sendable {
    let email: String      // "nome.cognome@studenti.unimi.it" (username CAS)
    let password: String

    /// Ariel vuole la sola parte locale in `tbLogin` e il dominio in `ddlType`.
    var localPart: String { email.split(separator: "@").first.map(String.init) ?? email }
    var domain: String { email.contains("@") ? "@" + (email.split(separator: "@").last.map(String.init) ?? "") : "@studenti.unimi.it" }
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
