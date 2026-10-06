import Foundation

/// Versione dimostrativa (per App Review, TestFlight e chi vuole provare l'app senza un account d'Ateneo).
/// Con le credenziali qui sotto l'app non contatta UNIMIA, SIFA, Ariel né le API dell'Agenda: ogni servizio
/// restituisce i dati di `DatiDemo` (studente, corso e docenti inventati, date calcolate a partire da oggi).
/// Trascrizioni, riassunti e download dei modelli funzionano come nella versione normale.
nonisolated enum Demo {
    static let email = "tester@apple-developer.com"
    static let password = "StatalePlus-Demo"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var valore = false

    /// Vale per tutta l'app; si attiva all'accesso con le credenziali demo e si spegne all'uscita.
    static var attiva: Bool {
        get { lock.lock(); defer { lock.unlock() }; return valore }
        set { lock.lock(); valore = newValue; lock.unlock() }
    }

    static func credenzialiDemo(email: String, password: String) -> Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == Self.email && password == Self.password
    }

    /// Breve attesa come per una vera richiesta di rete, così caricamenti e pull-to-refresh si vedono.
    static func attesa() async {
        try? await Task.sleep(for: .milliseconds(Int.random(in: 250...600)))
    }
}

/// Registrazioni della demo: una lezione già trascritta e riassunta (audio, trascrizione e riassunto veri, fatti
/// con Parakeet e Qwen su una lezione letta da una voce sintetica) e una da trascrivere, per provare il flusso.
extension RecordingStore {
    private static let idDemoTrascritta = UUID(uuidString: "D3E00000-0000-4000-8000-000000000001")!
    private static let idDemoDaTrascrivere = UUID(uuidString: "D3E00000-0000-4000-8000-000000000002")!

    func preparaDemo() {
        guard let audio = Bundle.main.url(forResource: "demo-lezione", withExtension: "m4a") else { return }
        let cal = Formats.calendar
        let voci: [(UUID, DatiDemo.Corso, Int, Bool)] = [
            (Self.idDemoTrascritta, DatiDemo.corsi[0], -2, true),
            (Self.idDemoDaTrascrivere, DatiDemo.corsi[1], -1, false),
        ]
        for (id, corso, giorni, completa) in voci where item(id) == nil {
            let destinazione = folder.appending(path: "\(id.uuidString).m4a")
            try? FileManager.default.removeItem(at: destinazione)
            guard (try? FileManager.default.copyItem(at: audio, to: destinazione)) != nil else { continue }
            let giorno = cal.date(byAdding: .day, value: giorni, to: .now) ?? .now
            let creata = Formats.at(giorno, corso.orari[0].dalle) ?? giorno
            add(Registrazione(id: id, titolo: Registrazione.titoloPredefinito(insegnamento: corso.nome, creata: creata),
                              codiceInsegnamento: corso.codice, insegnamento: corso.nome, creata: creata, durata: 360,
                              file: "\(id.uuidString).m4a", segnalibri: completa ? [62, 215] : [],
                              note: completa ? "Ripassare il marcatore somatico e le critiche all'Iowa Gambling Task." : ""))
            if completa,
               let t = Bundle.main.url(forResource: "demo-trascrizione", withExtension: "txt").flatMap({ try? String(contentsOf: $0, encoding: .utf8) }),
               let r = Bundle.main.url(forResource: "demo-riassunto", withExtension: "md").flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) {
                salvaTrascrizione(id, t)
                salvaRiassunto(id, r)
            }
        }
    }
}
