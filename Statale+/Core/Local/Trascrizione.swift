import AVFoundation
import Speech

/// Trascrizione delle registrazioni con il framework Speech di Apple, in italiano.
/// - iOS 26+: `SpeechAnalyzer` + `SpeechTranscriber`, on-device e pensato per audio lunghi
///   (il modello della lingua viene scaricato la prima volta tramite `AssetInventory`).
/// - iOS 17–25: `SFSpeechRecognizer` a blocchi di 50 secondi (on-device se supportato), con punteggiatura.
nonisolated enum Trascrittore {
    static let lingua = Formats.it

    enum Errore: LocalizedError {
        case nonAutorizzato, nonDisponibile, linguaNonSupportata, vuota
        var errorDescription: String? {
            switch self {
            case .nonAutorizzato: "Consenti il riconoscimento vocale da Impostazioni › Statale+."
            case .nonDisponibile: "Il riconoscimento vocale non è disponibile in questo momento."
            case .linguaNonSupportata: "La trascrizione in italiano non è supportata su questo dispositivo."
            case .vuota: "Nessun parlato riconosciuto nella registrazione."
            }
        }
    }

    /// Trascrive il file audio. `progresso` riceve (0…1, messaggio di stato).
    @concurrent
    static func trascrivi(_ url: URL, progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        var testo: String?
        if #available(iOS 26.0, *), SpeechTranscriber.isAvailable {
            do { testo = try await conAnalyzer(url, progresso: progresso) } catch Errore.linguaNonSupportata { testo = nil }
        }
        if testo == nil { testo = try await conRecognizer(url, progresso: progresso) }
        let pulito = paragrafi(testo ?? "")
        guard !pulito.isEmpty else { throw Errore.vuota }
        return pulito
    }

    // MARK: iOS 26+

    @available(iOS 26.0, *)
    private static func conAnalyzer(_ url: URL, progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: lingua) else { throw Errore.linguaNonSupportata }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let richiesta = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            progresso(0, "Download del modello di trascrizione in italiano…")
            try await richiesta.downloadAndInstall()
        }
        let file = try AVAudioFile(forReading: url)
        let durata = Double(file.length) / file.processingFormat.sampleRate
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let raccolta = Task {
            var parti: [String] = []
            for try await r in transcriber.results {
                parti.append(String(r.text.characters))
                if durata > 0 { progresso(min(0.99, r.range.end.seconds / durata), "Trascrizione in corso…") }
            }
            return parti.joined(separator: " ")
        }
        progresso(0, "Trascrizione in corso…")
        do {
            if let fine = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: fine)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            raccolta.cancel()
            throw error
        }
        return try await withTaskCancellationHandler {
            try await raccolta.value
        } onCancel: {
            raccolta.cancel()
        }
    }

    // MARK: iOS 17–25

    private static func conRecognizer(_ url: URL, progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        let stato = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard stato == .authorized else { throw Errore.nonAutorizzato }
        guard let recognizer = SFSpeechRecognizer(locale: lingua) else { throw Errore.linguaNonSupportata }
        guard recognizer.isAvailable else { throw Errore.nonDisponibile }

        let file = try AVAudioFile(forReading: url)
        let formato = file.processingFormat
        let blocco = AVAudioFrameCount(formato.sampleRate * 50)
        let totale = max(file.length, 1)
        var parti: [String] = []
        progresso(0, "Trascrizione in corso…")
        while file.framePosition < file.length {
            try Task.checkCancellation()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: blocco) else { break }
            try file.read(into: buffer, frameCount: blocco)
            guard buffer.frameLength > 0 else { break }
            let richiesta = SFSpeechAudioBufferRecognitionRequest()
            richiesta.shouldReportPartialResults = false
            richiesta.addsPunctuation = true
            richiesta.taskHint = .dictation
            if recognizer.supportsOnDeviceRecognition { richiesta.requiresOnDeviceRecognition = true }
            richiesta.append(buffer)
            richiesta.endAudio()
            let testo = try await riconosci(recognizer, richiesta)
            if !testo.isEmpty { parti.append(testo) }
            progresso(Double(file.framePosition) / Double(totale), "Trascrizione in corso…")
        }
        return parti.joined(separator: " ")
    }

    private static func riconosci(_ recognizer: SFSpeechRecognizer, _ richiesta: SFSpeechAudioBufferRecognitionRequest) async throws -> String {
        let once = UnaVolta()
        return try await withCheckedThrowingContinuation { c in
            recognizer.recognitionTask(with: richiesta) { risultato, errore in
                if let risultato, risultato.isFinal {
                    let testo = risultato.bestTranscription.formattedString
                    once.esegui { c.resume(returning: testo) }
                } else if let errore {
                    // 1110 = nessun parlato nel blocco: non è un errore per una lezione con pause.
                    let silenzio = (errore as NSError).code == 1110
                    once.esegui { silenzio ? c.resume(returning: "") : c.resume(throwing: errore) }
                }
            }
        }
    }

    // MARK: Formattazione

    /// Testo continuo → paragrafi di circa 5 frasi, per la lettura e per i Writing Tools.
    static func paragrafi(_ testo: String) -> String {
        let pulito = testo.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !pulito.isEmpty else { return "" }
        var frasi: [String] = []
        pulito.enumerateSubstrings(in: pulito.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty { frasi.append(s) }
        }
        if frasi.isEmpty { return pulito }
        return stride(from: 0, to: frasi.count, by: 5)
            .map { frasi[$0..<min($0 + 5, frasi.count)].joined(separator: " ") }
            .joined(separator: "\n\n")
    }
}

/// Esegue un blocco una sola volta anche se chiamato da thread diversi (callback di Speech).
nonisolated private final class UnaVolta: @unchecked Sendable {
    private let lock = NSLock()
    private var fatto = false
    func esegui(_ blocco: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !fatto else { return }
        fatto = true
        blocco()
    }
}
