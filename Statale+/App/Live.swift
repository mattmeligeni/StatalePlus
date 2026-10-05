import Foundation
import Observation

/// Stato di un dato live: fetch all'apertura, pull-to-refresh, "aggiornato alle HH:MM". Solo in memoria.
/// Un nuovo `load` rende obsoleto quello in corso (es. cambio di semestre durante il caricamento).
@Observable
final class Live<Value> {
    private(set) var value: Value?
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var updatedAt: Date?
    private var generation = 0

    init(_ initial: Value? = nil) { value = initial }

    func load(_ operation: () async throws -> Value) async {
        generation += 1
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let v = try await operation()
            guard current == generation else { return }
            value = v
            error = nil
            updatedAt = .now
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            guard current == generation else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Carica solo se mai caricato (apertura schermata); il pull-to-refresh usa `load`.
    func loadIfNeeded(_ operation: () async throws -> Value) async {
        guard updatedAt == nil, !isLoading else { return }
        await load(operation)
    }

    func set(_ v: Value) { value = v; error = nil; updatedAt = .now }

    /// Trasforma il valore già caricato senza cambiarne la data di aggiornamento (es. modifiche locali).
    func aggiorna(_ f: (Value) -> Value) { if let value { self.value = f(value) } }

    func reset() { generation += 1; value = nil; error = nil; updatedAt = nil; isLoading = false }
}
