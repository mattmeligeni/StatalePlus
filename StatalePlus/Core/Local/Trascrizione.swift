import AVFoundation
import Speech

/// Trascrizione delle registrazioni in italiano: Parakeet (se scelto e scaricato) oppure il framework Speech di Apple.
/// - `SpeechAnalyzer` + `SpeechTranscriber`, on-device e pensato per audio lunghi (il modello della lingua viene
///   scaricato la prima volta tramite `AssetInventory`);
/// - se `SpeechTranscriber` non è disponibile su questo iPhone: `SFSpeechRecognizer` a blocchi di 50 secondi
///   (on-device se supportato), con punteggiatura.
nonisolated enum Trascrittore {
    static let lingua = Formats.it

    enum Errore: LocalizedError {
        case nonAutorizzato, nonDisponibile, linguaNonSupportata, vuota
        var errorDescription: String? {
            switch self {
            case .nonAutorizzato: "Consenti il riconoscimento vocale da Impostazioni › Statale Plus."
            case .nonDisponibile: "Il riconoscimento vocale non è disponibile in questo momento."
            case .linguaNonSupportata: "La trascrizione in italiano non è supportata su questo dispositivo."
            case .vuota: "Nessun parlato riconosciuto nella registrazione."
            }
        }
    }

    /// Trascrive il file audio con il motore scelto in Altro › IA. `progresso` riceve (0…1, messaggio di stato).
    /// Niente parole di contesto (`AnalysisContext.contextualStrings`): provate con un vocabolario di 63 termini su una
    /// lezione di 2 ore e mezza, con `SpeechTranscriber` il testo resta identico byte per byte.
    @concurrent
    static func trascrivi(_ url: URL, motore: MotoreTrascrizione = .apple,
                          progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        if motore == .parakeet {
            let durata = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
            return paragrafi(try await ParakeetLocale.trascrivi(url, durata: durata, progresso: progresso))
        }
        var testo: String?
        if SpeechTranscriber.isAvailable {
            do { testo = try await conAnalyzer(url, progresso: progresso) } catch Errore.linguaNonSupportata { testo = nil }
        }
        if testo == nil {
            do { testo = try await conRecognizer(url, progresso: progresso) } catch let e as NSError where e.domain != NSCocoaErrorDomain && !(e is Errore) {
                // Errori interni di Speech (in inglese, es. "Failed to initialize recognizer"): messaggio comprensibile.
                throw Errore.nonDisponibile
            }
        }
        let pulito = paragrafi(testo ?? "")
        guard !pulito.isEmpty else { throw Errore.vuota }
        return pulito
    }

    // MARK: SpeechAnalyzer

    private static func conAnalyzer(_ url: URL,
                                    progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: lingua) else { throw Errore.linguaNonSupportata }
        // `.transcription`: il preset "accurato" (niente risultati rapidi o provvisori, che sacrificano precisione).
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
                if durata > 0 { progresso(min(0.99, r.range.end.seconds / durata), faseTrascrizione(r.range.end.seconds, di: durata)) }
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

    // MARK: Ripiego senza SpeechTranscriber

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
            progresso(Double(file.framePosition) / Double(totale),
                      faseTrascrizione(Double(file.framePosition) / formato.sampleRate, di: Double(file.length) / formato.sampleRate))
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

    /// "Neuroscienze cognitive dello sviluppo" → la frase intera e le parole significative (più di 3 lettere).
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

/// "Trascritti 12 di 80 min" (nell'app e nell'attività di sistema); sotto i 2 minuti in secondi.
nonisolated func faseTrascrizione(_ fatto: Double, di totale: Double) -> String {
    if totale < 120 { return "Trascritti \(Int(fatto)) di \(Int(totale)) s" }
    return "Trascritti \(Int(fatto / 60)) di \(Int((totale / 60).rounded())) min"
}
