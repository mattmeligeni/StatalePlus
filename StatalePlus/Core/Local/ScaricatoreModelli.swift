import Foundation

/// Cartella e download dei modelli locali (Parakeet, Qwen) in `Application Support/Modelli`, esclusa dal backup iCloud.
/// L'avanzamento è sempre in byte, così la barra si muove in modo regolare anche sui file da centinaia di MB.
nonisolated enum ScaricatoreModelli {
    static var cartellaBase: URL {
        URL.applicationSupportDirectory.appending(path: "Modelli", directoryHint: .isDirectory)
    }

    static func preparaCartellaBase() throws {
        try FileManager.default.createDirectory(at: cartellaBase, withIntermediateDirectories: true)
        var base = cartellaBase
        var valori = URLResourceValues()
        valori.isExcludedFromBackup = true
        try? base.setResourceValues(valori)
    }

    /// Byte occupati da una cartella (ricorsivo).
    static func dimensione(_ cartella: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: cartella, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return e.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
            .reduce(0) { $0 + Int64($1) }
    }

    /// Scarica tutti i file di un repository Hugging Face (es. "mlx-community/Qwen3.5-0.8B-4bit") in `cartella`.
    /// I file già presenti con la dimensione giusta non si riscaricano (download ripreso dopo un'interruzione).
    static func scaricaRepository(_ repo: String, in cartella: URL, escludi: Set<String> = ["README.md", ".gitattributes"],
                                  progresso: @escaping @Sendable (Double) -> Void) async throws {
        try preparaCartellaBase()
        try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        let elenco = try await fileDelRepository(repo).filter { !escludi.contains($0.percorso) }
        let totale = max(elenco.reduce(0) { $0 + $1.byte }, 1)
        var completati: Int64 = 0
        for file in elenco {
            try Task.checkCancellation()
            let destinazione = cartella.appending(path: file.percorso)
            if let presente = try? destinazione.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(presente) == file.byte {
                completati += file.byte
                progresso(Double(completati) / Double(totale))
                continue
            }
            let base = completati
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file.percorso)")!
            let temporaneo = try await DownloadConAvanzamento.scarica(url) { scritti in
                progresso(Double(base + scritti) / Double(totale))
            }
            try? FileManager.default.removeItem(at: destinazione)
            try FileManager.default.createDirectory(at: destinazione.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: temporaneo, to: destinazione)
            completati += file.byte
        }
        progresso(1)
    }

    private struct FileRemoto: Decodable {
        let type: String
        let path: String
        let size: Int64?
        var percorso: String { path }
        var byte: Int64 { size ?? 0 }
    }

    private static func fileDelRepository(_ repo: String) async throws -> [FileRemoto] {
        let url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main?recursive=true")!
        let (dati, risposta) = try await URLSession.shared.data(from: url)
        guard (risposta as? HTTPURLResponse)?.statusCode == 200 else { throw Errore.elencoNonDisponibile }
        return try JSONDecoder().decode([FileRemoto].self, from: dati).filter { $0.type == "file" }
    }

    enum Errore: LocalizedError {
        case elencoNonDisponibile, downloadNonRiuscito
        var errorDescription: String? {
            switch self {
            case .elencoNonDisponibile: "Impossibile raggiungere il server dei modelli. Controlla la connessione e riprova."
            case .downloadNonRiuscito: "Download del modello non riuscito. Riprova con una connessione stabile."
            }
        }
    }
}

/// Un file scaricato con `URLSessionDownloadTask`, con i byte scritti man mano.
private nonisolated final class DownloadConAvanzamento: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let avanzamento: @Sendable (Int64) -> Void
    private var continuazione: CheckedContinuation<URL, Error>?
    private let lock = NSLock()

    private init(avanzamento: @escaping @Sendable (Int64) -> Void) { self.avanzamento = avanzamento }

    static func scarica(_ url: URL, avanzamento: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let d = DownloadConAvanzamento(avanzamento: avanzamento)
        let sessione = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
        defer { sessione.finishTasksAndInvalidate() }
        let compito = sessione.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in
                d.lock.lock(); d.continuazione = c; d.lock.unlock()
                compito.resume()
            }
        } onCancel: {
            compito.cancel()
        }
    }

    private func concludi(_ r: Result<URL, Error>) {
        lock.lock(); let c = continuazione; continuazione = nil; lock.unlock()
        c?.resume(with: r)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        avanzamento(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Il file temporaneo sparisce alla fine di questo metodo: lo si sposta subito.
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            concludi(.failure(ScaricatoreModelli.Errore.downloadNonRiuscito)); return
        }
        let copia = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: copia)
            concludi(.success(copia))
        } catch {
            concludi(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            concludi(.failure((error as NSError).code == NSURLErrorCancelled ? CancellationError() : error))
        }
    }
}
