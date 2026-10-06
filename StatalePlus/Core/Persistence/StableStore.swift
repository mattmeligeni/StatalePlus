import Foundation
import Observation

/// Solo dati STABILI: profilo, configurazione Agenda, offerta Ariel e schede insegnamento con timestamp.
/// Orario, appelli, tasse, presenze, aule, esiti e partecipanti restano SOLO in memoria.
nonisolated struct StableSnapshot: Codable, Sendable {
    var studente: Studente?
    var agenda: AgendaConfig?
    var offerta: [InsegnamentoOfferta]?
    var offertaAggiornata: Date?
    var schede: [String: SchedaCache] = [:]
    var profiloAggiornato: Date?
}

nonisolated struct SchedaCache: Codable, Sendable {
    let scheda: SchedaInsegnamento
    let aggiornata: Date
}

@Observable
final class StableStore {
    static let ttlProfilo: TimeInterval = 24 * 3600
    static let ttlAgenda: TimeInterval = 7 * 24 * 3600
    static let ttlOfferta: TimeInterval = 24 * 3600
    static let ttlScheda: TimeInterval = 7 * 24 * 3600

    private(set) var snapshot: StableSnapshot
    private let url: URL

    init() {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appending(path: "stable.json")
        snapshot = (try? JSONDecoder().decode(StableSnapshot.self, from: Data(contentsOf: url))) ?? StableSnapshot()
    }

    func update(_ change: (inout StableSnapshot) -> Void) {
        change(&snapshot)
        do {
            try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
            var u = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true // è una cache ricostruibile
            try? u.setResourceValues(values)
        } catch {
            // La cache è di comodo: se non si scrive, l'app resta funzionante (dati live).
        }
    }

    func isStale(_ date: Date?, ttl: TimeInterval) -> Bool {
        guard let date else { return true }
        return Date.now.timeIntervalSince(date) > ttl
    }

    func wipe() {
        snapshot = StableSnapshot()
        try? FileManager.default.removeItem(at: url)
    }
}
