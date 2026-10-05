import BackgroundTasks
import Foundation
import UIKit

/// Lavori lunghi avviati dall'utente (trascrizione, riassunto, miglioramento dell'audio, download dei modelli)
/// che devono poter continuare se l'app va in background.
/// - iOS 26+: `BGContinuedProcessingTask`. Il lavoro parte in primo piano; se si esce dall'app iOS lo lascia
///   proseguire e ne mostra l'avanzamento in un'attività in tempo reale, da cui si può anche annullare. Ogni lavoro
///   ha un identificativo proprio (`…elaborazione.<uuid>`, ammesso dal carattere jolly in Info.plist).
/// - L'attività in tempo reale è quella di sistema (non personalizzabile): il titolo dice il lavoro, il sottotitolo
///   la fase attuale e il tempo stimato, aggiornati man mano.
/// - GPU ("Background GPU Access") e, da iOS 27, Neural Engine ("Background Inference") in background richiedono
///   entitlement che gli account sviluppatore personali non hanno: quei lavori si mettono in pausa e riprendono in
///   primo piano (`ElaborazioniAudio`).
/// - Versioni precedenti, o se il sistema non può avviarlo subito: si esegue normalmente chiedendo il tempo extra
///   di `beginBackgroundTask` (circa 30 secondi), poi il lavoro si sospende con l'app e riprende al ritorno.
nonisolated enum EsecuzioneEstesa {
    static let prefisso = (Bundle.main.bundleIdentifier ?? "com.mattiameligeni.Statale-") + ".elaborazione."

    /// Esegue `operazione`; `avanzamento(p, fase)` (p in 0…1) aggiorna l'attività di sistema.
    /// `sottotitolo` si vede solo finché non arriva la prima fase.
    static func esegui<T: Sendable>(titolo: String, sottotitolo: String,
                                    operazione: @escaping @Sendable (_ avanzamento: Avanzamento) async throws -> T) async throws -> T {
        if #available(iOS 26.0, *) {
            if let risultato = try await continuata(titolo: titolo, sottotitolo: sottotitolo, operazione: operazione) {
                return risultato.valore
            }
        }
        return try await conTempoExtra(titolo: titolo, operazione: operazione)
    }

    @available(iOS 26.0, *)
    private static func continuata<T: Sendable>(titolo: String, sottotitolo: String,
                                                operazione: @escaping @Sendable (Avanzamento) async throws -> T) async throws -> Risultato<T>? {
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
                    let sistema = CompitoDiSistema(task, titolo: titolo, sottotitolo: sottotitolo)
                    let lavoro = Task {
                        do {
                            let valore = try await operazione(Avanzamento { p, fase in sistema.avanzamento(p, fase: fase) })
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
                                                   operazione: @escaping @Sendable (Avanzamento) async throws -> T) async throws -> T {
        let id = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: titolo) }
        defer { Task { @MainActor in if id != .invalid { UIApplication.shared.endBackgroundTask(id) } } }
        return try await operazione(Avanzamento { _, _ in })
    }
}

/// Avanzamento di un lavoro: `avanzamento(0.4)` o `avanzamento(0.4, fase: "Parte 3 di 8")`.
nonisolated struct Avanzamento: Sendable {
    let aggiorna: @Sendable (Double, String?) -> Void
    func callAsFunction(_ p: Double, fase: String? = nil) { aggiorna(p, fase) }
}

/// Il task di sistema non è `Sendable`: lo si usa solo per avanzamento, titoli e conclusione (protetti dal lock).
/// Il sottotitolo mostra la fase e il tempo che manca, stimato dalla velocità media; cambia al massimo ogni 3 secondi.
@available(iOS 26.0, *)
private nonisolated final class CompitoDiSistema: @unchecked Sendable {
    private let task: BGContinuedProcessingTask
    private let titolo: String
    private let base: String
    private let inizio = Date()
    private let lock = NSLock()
    private var fase: String?
    private var ultimoSottotitolo = ""
    private var ultimoAggiornamento = Date.distantPast

    init(_ task: BGContinuedProcessingTask, titolo: String, sottotitolo: String) {
        self.task = task
        self.titolo = titolo
        self.base = sottotitolo
    }

    func avanzamento(_ p: Double, fase nuova: String?) {
        let p = min(max(p, 0), 1)
        lock.lock(); defer { lock.unlock() }
        task.progress.completedUnitCount = Int64(p * 1000)
        let cambiata = nuova != nil && nuova != fase
        if let nuova { fase = nuova }
        guard cambiata || Date().timeIntervalSince(ultimoAggiornamento) >= 3 else { return }
        // L'attività di sistema mostra una sola riga di sottotitolo: fase e tempo rimanente, senza ripetere il titolo.
        let sottotitolo = [fase ?? base, Self.rimanente(p, trascorso: Date().timeIntervalSince(inizio))]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
        guard sottotitolo != ultimoSottotitolo else { return }
        ultimoSottotitolo = sottotitolo
        ultimoAggiornamento = Date()
        task.updateTitle(titolo, subtitle: sottotitolo)
    }

    func concluso(_ ok: Bool) { task.setTaskCompleted(success: ok) }

    private static func rimanente(_ p: Double, trascorso: TimeInterval) -> String? { tempoRimanente(p, trascorso: trascorso) }
}

/// "circa 4 min" dopo almeno 10 secondi e il 3%: prima la stima oscilla troppo.
nonisolated func tempoRimanente(_ p: Double, trascorso: TimeInterval) -> String? {
    guard p >= 0.03, p < 1, trascorso >= 10 else { return nil }
    let minuti = Int((trascorso * (1 - p) / p / 60).rounded(.up))
    return minuti <= 1 ? "meno di un minuto" : "circa \(minuti) min"
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
