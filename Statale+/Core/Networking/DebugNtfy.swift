import Foundation

/// Solo nelle build di debug: ogni chiamata di timbratura invia l'esito a ntfy.sh/StatalePlus, per seguire dal
/// telefono cosa risponde il server in aula. I topic di ntfy.sh sono pubblici: non si inviano matricola né altri
/// dati personali, solo codice lezione, stato HTTP e risposta del server. Nelle build di rilascio non fa nulla.
nonisolated enum DebugNtfy {
    static func timbratura(codice: String, esito: String, dettaglio: String) {
        #if DEBUG
        let testo = """
            Esito: \(esito)
            Codice lezione: \(codice.isEmpty ? "(vuoto)" : codice)
            Risposta: \(dettaglio.isEmpty ? "(vuota)" : dettaglio)
            Ora: \(Date.now.formatted(.iso8601))
            """
        guard let url = URL(string: "https://ntfy.sh/StatalePlus") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(testo.utf8)
        req.setValue("Statale+ timbratura", forHTTPHeaderField: "Title")
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        Task.detached(priority: .utility) { _ = try? await URLSession.shared.data(for: req) }
        #endif
    }
}
