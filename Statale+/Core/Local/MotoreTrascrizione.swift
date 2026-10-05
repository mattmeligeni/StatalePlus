import FluidAudio
import Foundation

/// Motori di trascrizione selezionabili in Altro › IA › Trascrizione.
nonisolated enum MotoreTrascrizione: String, CaseIterable, Sendable {
    /// Speech di Apple (`SpeechAnalyzer`/`SpeechTranscriber`), sul dispositivo: veloce, leggero, nessun download.
    case apple
    /// NVIDIA Parakeet TDT 0.6B v3 "Ultra" con FluidAudio (Core ML sul Neural Engine): più accurato, download di ~630 MB.
    case parakeet
    /// Trascrizione remota a pagamento: non ancora disponibile.
    case remoto

    var nome: String {
        switch self {
        case .apple: "Apple"
        case .parakeet: "Parakeet"
        case .remoto: "Remoto Pro"
        }
    }

    var caratteristiche: [String] {
        switch self {
        case .apple: ["Sul dispositivo", "Privato", "Nessun download"]
        case .parakeet: ["Sul dispositivo", "Privato", "Più accurato", "Download di \(ParakeetLocale.dimensioneMB) MB"]
        case .remoto: ["A pagamento", "Presto disponibile"]
        }
    }

    var descrizione: String {
        switch self {
        case .apple:
            "Riconoscimento vocale di Apple in italiano. Non richiede download, ma sbaglia più spesso termini tecnici e nomi, soprattutto con l'audio registrato da lontano."
        case .parakeet:
            "Parakeet di NVIDIA, eseguito sul Neural Engine. Riconosce meglio termini tecnici e nomi, mette la punteggiatura ed è velocissimo: una lezione di due ore in pochi minuti, con pochi consumi."
        case .remoto:
            "Trascrizione su server con modelli professionali, per la massima accuratezza. Sarà un'opzione a pagamento."
        }
    }
}

/// Parakeet TDT 0.6B v3 nella versione "Ultra" (riaddestramento di moondream: stesse lingue, più preciso) con
/// FluidAudio. Sul Mac una lezione di 2 h 25 min si trascrive in 40 s con 92 MB di memoria (Whisper: 16-19 minuti).
/// I file stanno in `Application Support/Modelli/<repo>` (esclusi dal backup), con un marcatore scritto a download finito.
nonisolated enum ParakeetLocale {
    static let versione: AsrModelVersion = .ultra
    static let dimensioneMB = 632
    /// Byte totali dei file del modello, per l'avanzamento del download.
    static let byteTotali: Int64 = 632_314_500

    /// FluidAudio scarica in `<cartella madre>/<nome del repository>`: la cartella deve chiamarsi così.
    static var cartella: URL {
        ScaricatoreModelli.cartellaBase.appending(path: AsrModels.defaultCacheDirectory(for: versione).lastPathComponent,
                                                  directoryHint: .isDirectory)
    }

    private static var conferma: URL { ScaricatoreModelli.cartellaBase.appending(path: "installato-parakeet-ultra") }

    static var installato: Bool {
        FileManager.default.fileExists(atPath: conferma.path(percentEncoded: false))
            && AsrModels.modelsExist(at: cartella, version: versione)
    }

    static var spazioOccupato: Int64 { ScaricatoreModelli.dimensione(cartella) }

    @concurrent
    static func scarica(progresso: @escaping @Sendable (Double) -> Void) async throws {
        try ScaricatoreModelli.preparaCartellaBase()
        // L'avanzamento di FluidAudio riparte da zero per ogni file: si misurano i byte già nella cartella più quelli
        // dei file parziali che scrive nella cartella temporanea.
        let misura = Task {
            while !Task.isCancelled {
                let parziali = ((try? FileManager.default.contentsOfDirectory(at: .temporaryDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
                    .filter { $0.pathExtension == "partial" }
                    .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
                    .reduce(0) { $0 + Int64($1) }
                progresso(min(Double(spazioOccupato + parziali) / Double(byteTotali), 0.99))
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        defer { misura.cancel() }
        _ = try await AsrModels.download(to: cartella, version: versione)
        try Task.checkCancellation()
        guard AsrModels.modelsExist(at: cartella, version: versione) else { throw Errore.downloadIncompleto }
        try Data().write(to: conferma)
        progresso(1)
    }

    static func elimina() {
        try? FileManager.default.removeItem(at: cartella)
        try? FileManager.default.removeItem(at: conferma)
    }

    enum Errore: LocalizedError {
        case nonInstallato, downloadIncompleto, vuota
        var errorDescription: String? {
            switch self {
            case .nonInstallato: "Il modello Parakeet non è scaricato: scaricalo da Altro › IA › Trascrizione."
            case .downloadIncompleto: "Download del modello Parakeet incompleto. Riprova con una connessione stabile."
            case .vuota: "Nessun parlato riconosciuto nella registrazione."
            }
        }
    }

    /// Trascrive in italiano leggendo il file a blocchi dal disco (memoria costante anche per lezioni di ore).
    @concurrent
    static func trascrivi(_ url: URL, durata: TimeInterval,
                          progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard installato else { throw Errore.nonInstallato }
        progresso(0, "Caricamento del modello Parakeet…")
        let modelli = try await AsrModels.load(from: cartella, version: versione)
        let asr = AsrManager()
        try await asr.loadModels(modelli)
        let flusso = await asr.transcriptionProgressStream
        let osserva = Task {
            for try await p in flusso where durata > 0 {
                progresso(min(p, 0.99), faseTrascrizione(p * durata, di: durata))
            }
        }
        defer { osserva.cancel() }
        progresso(0, "Trascrizione con Parakeet…")
        var stato = TdtDecoderState.make()
        let risultato: ASRResult
        do {
            risultato = try await asr.transcribe(url, decoderState: &stato, language: .italian)
        } catch {
            await asr.cleanup()
            throw error
        }
        await asr.cleanup()
        try Task.checkCancellation()
        let testo = senzaRipetizioni(risultato.text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !testo.isEmpty else { throw Errore.vuota }
        return testo
    }
}

/// Ripulitura dei modelli non più usati (Whisper, sostituito da Parakeet: era più lento e su audio registrato da
/// lontano inventava frasi e ripeteva pezzi). Libera circa 630 MB a chi l'aveva scaricato.
nonisolated enum ModelliDismessi {
    static func elimina() {
        let fm = FileManager.default
        let base = ScaricatoreModelli.cartellaBase
        try? fm.removeItem(at: base.appending(path: "models/argmaxinc", directoryHint: .isDirectory))
        for f in (try? fm.contentsOfDirectory(atPath: base.path(percentEncoded: false))) ?? [] where f.hasPrefix("installato-openai_whisper") {
            try? fm.removeItem(at: base.appending(path: f))
        }
        if (try? fm.contentsOfDirectory(atPath: base.appending(path: "models").path(percentEncoded: false)))?.isEmpty == true {
            try? fm.removeItem(at: base.appending(path: "models"))
        }
    }
}

/// I modelli di trascrizione a volte "si inceppano" e ripetono lo stesso pezzo ("la valorezza la valorezza la
/// valorezza"): si tiene una sola copia di ogni gruppo di 1-8 parole ripetuto subito dopo (confronto senza
/// maiuscole e punteggiatura).
nonisolated func senzaRipetizioni(_ testo: String) -> String {
    func chiave(_ p: Substring) -> String { p.lowercased().filter { $0.isLetter || $0.isNumber } }
    var parole: [Substring] = []
    var chiavi: [String] = []
    for p in testo.split(separator: " ", omittingEmptySubsequences: true) {
        parole.append(p)
        chiavi.append(chiave(p))
        for n in stride(from: 8, through: 1, by: -1) where chiavi.count >= 2 * n {
            let k = chiavi.count
            if chiavi[(k - n)...] == chiavi[(k - 2 * n)..<(k - n)], !chiavi[(k - n)...].allSatisfy(\.isEmpty) {
                parole.removeLast(n)
                chiavi.removeLast(n)
                break
            }
        }
    }
    return parole.joined(separator: " ")
}
