import ActivityKit
import Foundation

/// La Live Activity di Statale+ (estensione `StatalePlusAttivita`): un'unica attività con tutti i lavori lunghi in
/// corso, aggiornata da `EsecuzioneEstesa` e dalle pause di `ElaborazioniAudio`.
/// - Si avvia al primo lavoro (iOS permette di avviarla solo con l'app in primo piano) e si chiude quando non ce ne
///   sono più, lasciando per qualche minuto l'ultimo esito ("Completato").
/// - Gli aggiornamenti si raggruppano: al massimo uno al secondo, o subito se cambia la fase o lo stato.
@MainActor
final class AttivitaLive {
    static let shared = AttivitaLive()

    typealias Lavoro = AttivitaElaborazioneAttributes.Lavoro

    private var activity: Activity<AttivitaElaborazioneAttributes>?
    private var lavori: [Lavoro] = []
    private var ultimoInvio = Date.distantPast
    private var invioPendente: Task<Void, Never>?

    private var attive: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func inizia(id: String, tipo: String, titolo: String, sottotitolo: String) {
        lavori.removeAll { $0.id == id || $0.concluso }
        lavori.append(Lavoro(id: id, tipo: tipo, titolo: titolo, sottotitolo: sottotitolo, progresso: 0,
                             fase: nil, rimanente: nil, inPausa: false, concluso: false))
        invia(subito: true)
    }

    func aggiorna(id: String, progresso: Double, fase: String?, rimanente: String?) {
        guard let i = lavori.firstIndex(where: { $0.id == id }) else { return }
        let cambiata = lavori[i].fase != fase || lavori[i].inPausa
        lavori[i].progresso = progresso
        if let fase { lavori[i].fase = fase }
        lavori[i].rimanente = rimanente
        lavori[i].inPausa = false
        invia(subito: cambiata)
    }

    func pausa(id: String, tipo: String, titolo: String, sottotitolo: String, progresso: Double) {
        if let i = lavori.firstIndex(where: { $0.id == id }) {
            lavori[i].inPausa = true
        } else {
            lavori.append(Lavoro(id: id, tipo: tipo, titolo: titolo, sottotitolo: sottotitolo, progresso: progresso,
                                 fase: nil, rimanente: nil, inPausa: true, concluso: false))
        }
        invia(subito: true)
    }

    func concludi(id: String, riuscito: Bool) {
        guard let i = lavori.firstIndex(where: { $0.id == id }) else { return }
        if riuscito {
            lavori[i].concluso = true
            lavori[i].progresso = 1
        } else {
            lavori.remove(at: i)
        }
        if lavori.allSatisfy(\.concluso) {
            chiudi()
        } else {
            invia(subito: true)
        }
    }

    /// Toglie un lavoro in pausa che è ripartito con un altro identificativo (o è stato annullato).
    func rimuovi(id: String) {
        lavori.removeAll { $0.id == id }
        if lavori.isEmpty { chiudi() } else { invia(subito: true) }
    }

    private func stato() -> AttivitaElaborazioneAttributes.ContentState {
        // In cima i lavori in corso, poi quelli in pausa, infine i conclusi.
        .init(lavori: lavori.sorted { ordine($0) < ordine($1) })
    }

    private func ordine(_ l: Lavoro) -> Int { l.concluso ? 2 : l.inPausa ? 1 : 0 }

    private func invia(subito: Bool) {
        guard attive else { return }
        // Chiusa dall'utente o dal sistema: alla prossima occasione se ne apre una nuova.
        if let a = activity, a.activityState == .ended || a.activityState == .dismissed { activity = nil }
        if activity == nil {
            activity = try? Activity.request(attributes: AttivitaElaborazioneAttributes(),
                                             content: .init(state: stato(), staleDate: nil), pushType: nil)
            ultimoInvio = Date()
            return
        }
        let attesa = 1 - Date().timeIntervalSince(ultimoInvio)
        if subito || attesa <= 0 {
            invioPendente?.cancel()
            invioPendente = nil
            ultimoInvio = Date()
            let contenuto = ActivityContent(state: stato(), staleDate: nil)
            if let a = activity.map(Riferimento.init) { Task { await a.attivita.update(contenuto) } }
        } else if invioPendente == nil {
            invioPendente = Task {
                try? await Task.sleep(for: .seconds(attesa))
                guard !Task.isCancelled else { return }
                self.invioPendente = nil
                self.invia(subito: true)
            }
        }
    }

    private func chiudi() {
        invioPendente?.cancel()
        invioPendente = nil
        guard let a = activity.map(Riferimento.init) else { lavori = []; return }
        let contenuto = ActivityContent(state: stato(), staleDate: nil)
        activity = nil
        lavori = []
        Task { await a.attivita.end(contenuto, dismissalPolicy: .after(Date().addingTimeInterval(5 * 60))) }
    }
}

/// `Activity` non è dichiarato `Sendable`, ma `update` ed `end` si possono chiamare da qualsiasi contesto.
private nonisolated struct Riferimento: @unchecked Sendable {
    let attivita: Activity<AttivitaElaborazioneAttributes>
}
