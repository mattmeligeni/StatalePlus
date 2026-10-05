import BackgroundTasks
import Foundation
import UIKit

/// Lavori lunghi avviati dall'utente (trascrizione, riassunto, miglioramento dell'audio, download del modello Whisper)
/// che devono poter continuare se l'app va in background.
/// - iOS 26+: `BGContinuedProcessingTask`. Il lavoro parte in primo piano; se si esce dall'app iOS lo lascia
///   proseguire e ne mostra l'avanzamento in un'attività in tempo reale, da cui si può anche annullare. Ogni lavoro
///   ha un identificativo proprio (`…elaborazione.<uuid>`, ammesso dal carattere jolly in Info.plist).
/// - Versioni precedenti, o se il sistema non può avviarlo subito: si esegue normalmente chiedendo il tempo extra
///   di `beginBackgroundTask` (circa 30 secondi), poi il lavoro si sospende con l'app e riprende al ritorno.
nonisolated enum EsecuzioneEstesa {
    static let prefisso = (Bundle.main.bundleIdentifier ?? "com.mattiameligeni.Statale-") + ".elaborazione."

    /// Esegue `operazione`; `progresso` (0…1) aggiorna anche l'interfaccia di sistema.
    static func esegui<T: Sendable>(titolo: String, sottotitolo: String,
                                    operazione: @escaping @Sendable (_ progresso: @escaping @Sendable (Double) -> Void) async throws -> T) async throws -> T {
        if #available(iOS 26.0, *) {
            if let risultato = try await continuata(titolo: titolo, sottotitolo: sottotitolo, operazione: operazione) {
                return risultato.valore
            }
        }
        return try await conTempoExtra(titolo: titolo, operazione: operazione)
    }

    @available(iOS 26.0, *)
    private static func continuata<T: Sendable>(titolo: String, sottotitolo: String,
                                                operazione: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> T) async throws -> Risultato<T>? {
        let identificativo = prefisso + UUID().uuidString
        let stato = StatoContinuato<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Risultato<T>?, Error>) in
                stato.imposta(cont)
                let registrato = BGTaskScheduler.shared.register(forTaskWithIdentifier: identificativo, using: nil) { task in
                    guard let task = task as? BGContinuedProcessingTask else {
                        task.setTaskCompleted(success: false)
                        stato.concludi(.success(nil))
                        return
                    }
                    task.progress.totalUnitCount = 1000
                    let sistema = CompitoDiSistema(task)
                    let lavoro = Task {
                        do {
                            let valore = try await operazione { p in sistema.avanzamento(p) }
                            sistema.concluso(true)
                            stato.concludi(.success(Risultato(valore: valore)))
                        } catch {
                            sistema.concluso(false)
                            stato.concludi(.failure(error))
                        }
                    }
                    stato.lavoro(lavoro)
                    // Annullato dall'attività in tempo reale o dal sistema.
                    task.expirationHandler = { lavoro.cancel() }
                }
                guard registrato else { stato.concludi(.success(nil)); return }
                let richiesta = BGContinuedProcessingTaskRequest(identifier: identificativo, title: titolo, subtitle: sottotitolo)
                richiesta.strategy = .fail
                do { try BGTaskScheduler.shared.submit(richiesta) } catch { stato.concludi(.success(nil)) }
            }
        } onCancel: {
            stato.annulla()
        }
    }

    private static func conTempoExtra<T: Sendable>(titolo: String,
                                                   operazione: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> T) async throws -> T {
        let id = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: titolo) }
        defer { Task { @MainActor in if id != .invalid { UIApplication.shared.endBackgroundTask(id) } } }
        return try await operazione { _ in }
    }
}

/// Il task di sistema non è `Sendable`: lo si usa solo per avanzamento e conclusione, entrambi thread-safe.
@available(iOS 26.0, *)
private nonisolated final class CompitoDiSistema: @unchecked Sendable {
    private let task: BGContinuedProcessingTask
    init(_ task: BGContinuedProcessingTask) { self.task = task }
    func avanzamento(_ p: Double) { task.progress.completedUnitCount = Int64(min(max(p, 0), 1) * 1000) }
    func concluso(_ ok: Bool) { task.setTaskCompleted(success: ok) }
}

/// Avvolge il valore per distinguere "non avviato" (nil) da un risultato che a sua volta può essere opzionale.
private nonisolated struct Risultato<T: Sendable>: Sendable { let valore: T }

/// Stato condiviso fra il gestore del task di sistema (che gira su un'altra coda) e chi attende il risultato.
private nonisolated final class StatoContinuato<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuazione: CheckedContinuation<Risultato<T>?, Error>?
    private var compito: Task<Void, Never>?
    private var annullato = false

    func imposta(_ c: CheckedContinuation<Risultato<T>?, Error>) {
        lock.lock(); defer { lock.unlock() }
        continuazione = c
    }

    func lavoro(_ t: Task<Void, Never>) {
        lock.lock()
        compito = t
        let giaAnnullato = annullato
        lock.unlock()
        if giaAnnullato { t.cancel() }
    }

    func annulla() {
        lock.lock()
        annullato = true
        let t = compito
        lock.unlock()
        t?.cancel()
    }

    /// Riprende chi attende una sola volta.
    func concludi(_ r: Result<Risultato<T>?, Error>) {
        lock.lock()
        let c = continuazione
        continuazione = nil
        lock.unlock()
        c?.resume(with: r)
    }
}
