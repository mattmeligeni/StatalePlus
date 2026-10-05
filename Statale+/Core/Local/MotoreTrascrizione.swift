import Foundation
import WhisperKit

/// Motori di trascrizione selezionabili in Impostazioni › Trascrizione.
nonisolated enum MotoreTrascrizione: String, CaseIterable, Sendable {
    /// Speech di Apple (`SpeechAnalyzer`/`SpeechTranscriber`), sul dispositivo: veloce, leggero, nessun download.
    case apple
    /// OpenAI Whisper Large v3 Turbo tramite WhisperKit (Argmax), sul dispositivo: più accurato, download di ~630 MB.
    case whisper
    /// Trascrizione remota a pagamento: non ancora disponibile.
    case remoto

    var nome: String {
        switch self {
        case .apple: "Apple"
        case .whisper: "Whisper"
        case .remoto: "Remoto Pro"
        }
    }

    var caratteristiche: [String] {
        switch self {
        case .apple: ["Sul dispositivo", "Privato", "Veloce", "Leggero"]
        case .whisper: ["Sul dispositivo", "Privato", "Più accurato", "Download di \(WhisperLocale.dimensioneMB) MB"]
        case .remoto: ["A pagamento", "Presto disponibile"]
        }
    }

    var descrizione: String {
        switch self {
        case .apple:
            "Riconoscimento vocale di Apple in italiano, con il modello più accurato del sistema. Non richiede download aggiuntivi e consuma poca batteria."
        case .whisper:
            "Whisper Large v3 Turbo di OpenAI, eseguito sul dispositivo con WhisperKit. Più preciso su lezioni lunghe, termini tecnici e audio difficili, ma più pesante: consuma più batteria e richiede più tempo, soprattutto per le registrazioni lunghe."
        case .remoto:
            "Trascrizione su server con modelli professionali, per la massima accuratezza. Sarà un'opzione a pagamento."
        }
    }
}

/// Whisper sul dispositivo con WhisperKit (argmax-oss-swift).
/// Modello: `openai_whisper-large-v3-v20240930_626MB`, cioè Whisper Large v3 Turbo (OpenAI, 30-09-2024, il più recente)
/// compresso a 626 MB: è quello consigliato da Argmax per iOS e supportato dagli iPhone con chip A15 o successivi.
/// I file stanno in Application Support/Modelli (esclusi dal backup iCloud).
nonisolated enum WhisperLocale {
    static let variante = "openai_whisper-large-v3-v20240930_626MB"
    static let repo = "argmaxinc/whisperkit-coreml"
    static let dimensioneMB = 626
    /// Dimensione esatta dei file del modello, per l'avanzamento del download.
    static let byteTotali: Int64 = 626_720_156

    static var cartellaBase: URL {
        URL.applicationSupportDirectory.appending(path: "Modelli", directoryHint: .isDirectory)
    }

    /// Dove `WhisperKit.download` mette il modello (`<base>/models/<repo>/<variante>`).
    static var cartellaModello: URL {
        cartellaBase.appending(path: "models/\(repo)/\(variante)", directoryHint: .isDirectory)
    }

    /// Supportato su questo dispositivo secondo la tabella di Argmax (iPhone con A15 o successivi).
    static var supportato: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return WhisperKit.recommendedModels().supported.contains(variante)
        #endif
    }

    /// Scritto solo a download concluso: le cartelle dei modelli compaiono subito, mentre i file arrivano dopo.
    private static var conferma: URL { cartellaBase.appending(path: "installato-\(variante)") }

    /// Modello scaricato e completo (i modelli Core ML sono cartelle `.mlmodelc`).
    static var installato: Bool {
        let fm = FileManager.default
        let necessari = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]
        return fm.fileExists(atPath: conferma.path(percentEncoded: false))
            && necessari.allSatisfy { fm.fileExists(atPath: cartellaModello.appending(path: $0).path(percentEncoded: false)) }
    }

    static var spazioOccupato: Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: cartellaBase, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return e.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
            .reduce(0) { $0 + Int64($1) }
    }

    @concurrent
    static func scarica(progresso: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: cartellaBase, withIntermediateDirectories: true)
        var base = cartellaBase
        var valori = URLResourceValues()
        valori.isExcludedFromBackup = true
        try? base.setResourceValues(valori)
        // WhisperKit conta i file scaricati, non i byte: i file piccoli finiscono subito e poi l'avanzamento resta
        // fermo sui pesi da centinaia di MB. Si misura quindi quanto è già su disco (anche i file `.incomplete`).
        let misura = Task {
            while !Task.isCancelled {
                progresso(min(Double(spazioOccupato) / Double(byteTotali), 0.99))
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { misura.cancel() }
        _ = try await WhisperKit.download(variant: variante, downloadBase: cartellaBase, from: repo)
        try Task.checkCancellation()
        progresso(1)
        try Data().write(to: conferma)
        guard installato else { throw Errore.downloadIncompleto }
    }

    static func elimina() {
        try? FileManager.default.removeItem(at: cartellaBase)
    }

    enum Errore: LocalizedError {
        case nonInstallato, downloadIncompleto, vuota
        var errorDescription: String? {
            switch self {
            case .nonInstallato: "Il modello Whisper non è scaricato: scaricalo da Impostazioni › Trascrizione."
            case .downloadIncompleto: "Download del modello Whisper incompleto. Riprova con una connessione stabile."
            case .vuota: "Nessun parlato riconosciuto nella registrazione."
            }
        }
    }

    /// Frasi che Whisper "inventa" sui silenzi in italiano (sottotitoli dei video su cui è stato addestrato).
    private static let allucinazioni = [
        "sottotitoli creati dalla comunità amara.org", "sottotitoli a cura di", "sottotitoli e revisione a cura di",
        "grazie per la visione", "grazie a tutti per la visione", "iscriviti al canale", "qtss",
    ]

    /// Trascrive in italiano con caricamento incrementale (memoria limitata anche per lezioni di ore) e suddivisione
    /// sui silenzi. `progresso` riceve (0…1, messaggio).
    @concurrent
    static func trascrivi(_ url: URL, durata: TimeInterval,
                          progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard installato else { throw Errore.nonInstallato }
        progresso(0, "Caricamento del modello Whisper (la prima volta può richiedere qualche minuto)…")
        let config = WhisperKitConfig(model: variante, modelFolder: cartellaModello.path(percentEncoded: false),
                                      verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
        let pipe = try await WhisperKit(config)
        do {
            let testo = try await trascrivi(url, con: pipe, durata: durata, progresso: progresso)
            await pipe.unloadModels()
            return testo
        } catch {
            await pipe.unloadModels()
            throw error
        }
    }

    private static func trascrivi(_ url: URL, con pipe: WhisperKit, durata: TimeInterval,
                                  progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        try Task.checkCancellation()
        progresso(0, "Trascrizione con Whisper…")
        pipe.segmentDiscoveryCallback = { segmenti in
            guard durata > 0, let fine = segmenti.map(\.end).max() else { return }
            progresso(min(0.99, Double(fine) / durata), faseTrascrizione(Double(fine), di: durata))
        }
        let opzioni = DecodingOptions(task: .transcribe, language: "it", temperatureFallbackCount: 3,
                                      usePrefillPrompt: true, detectLanguage: false, skipSpecialTokens: true,
                                      withoutTimestamps: false, chunkingStrategy: .vad)
        let risultati = try await pipe.transcribe(audioPath: url.path(percentEncoded: false),
                                                  audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
                                                  decodeOptions: opzioni) { _ in Task.isCancelled ? false : nil }
        try Task.checkCancellation()
        let testo = risultati
            .flatMap(\.segments)
            .filter { $0.noSpeechProb < 0.6 }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { s in !s.isEmpty && !allucinazioni.contains { s.lowercased().contains($0) } }
            .joined(separator: " ")
        guard !testo.isEmpty else { throw Errore.vuota }
        return testo
    }
}
