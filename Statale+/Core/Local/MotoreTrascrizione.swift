import CoreML
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
        case .apple: ["Nessun download", "Veloce", "Offline"]
        case .parakeet: ["Download di \(ParakeetLocale.dimensioneMB) MB", "Più preciso", "Offline"]
        case .remoto: ["Online", "A pagamento", "Presto"]
        }
    }

    var descrizione: String {
        switch self {
        case .apple:
            "Il riconoscimento vocale di iPhone. Pronto subito, ma sbaglia più spesso termini tecnici e nomi."
        case .parakeet:
            "Riconosce meglio termini tecnici e nomi e mette la punteggiatura. Due ore di lezione in pochi minuti."
        case .remoto:
            "Più veloce e potente, ma l'audio viene inviato fuori dal telefono."
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

    /// Controllo rapido (all'avvio): ci sono tutti i file e occupano quanto devono. Un download interrotto lascia
    /// cartelle di modelli con solo una parte dei file, che FluidAudio da solo considererebbe complete.
    static var integro: Bool {
        installato && Double(spazioOccupato) >= Double(byteTotali) * 0.98
    }

    /// Scarica da capo (un download interrotto non si riprende: i file parziali sono nella cartella temporanea),
    /// poi verifica dimensione e caricamento dei modelli prima di dichiararlo pronto.
    /// Avanzamento: 0-90% download (in byte), 90-99% preparazione e verifica, che sul telefono richiedono qualche
    /// minuto: la barra continua a muoversi perché iOS chiude le attività in background che sembrano ferme.
    @concurrent
    static func scarica(progresso: @escaping @Sendable (Double, String) -> Void) async throws {
        try ScaricatoreModelli.preparaCartellaBase()
        elimina()
        let preparazione = InizioPreparazione()
        let misura = Task {
            while !Task.isCancelled {
                if let inizio = preparazione.inizio {
                    let t = Date().timeIntervalSince(inizio)
                    progresso(0.9 + 0.09 * (1 - exp(-t / 90)), "Preparazione del modello")
                } else {
                    let parziali = ((try? FileManager.default.contentsOfDirectory(at: .temporaryDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
                        .filter { $0.pathExtension == "partial" }
                        .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
                        .reduce(0) { $0 + Int64($1) }
                    let scaricati = min(spazioOccupato + parziali, byteTotali)
                    progresso(0.9 * Double(scaricati) / Double(byteTotali), "\(scaricati / 1_000_000) di \(dimensioneMB) MB")
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        defer { misura.cancel() }
        _ = try await AsrModels.download(to: cartella, version: versione) { p in
            if case .compiling = p.phase { preparazione.segna() }
        }
        try Task.checkCancellation()
        preparazione.segna()
        guard AsrModels.modelsExist(at: cartella, version: versione),
              Double(spazioOccupato) >= Double(byteTotali) * 0.98 else {
            elimina()
            throw Errore.downloadIncompleto
        }
        // Prova a caricare i modelli: se un file è rovinato si scopre ora, non alla prima trascrizione.
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuOnly
            _ = try await AsrModels.load(from: cartella, configuration: config, version: versione)
        } catch {
            elimina()
            throw Errore.downloadIncompleto
        }
        try Data().write(to: conferma)
        progresso(1, "Pronto")
    }

    static func elimina() {
        try? FileManager.default.removeItem(at: cartella)
        try? FileManager.default.removeItem(at: conferma)
    }

    enum Errore: LocalizedError {
        case nonInstallato, downloadIncompleto, danneggiato, vuota
        var errorDescription: String? {
            switch self {
            case .nonInstallato: "Il modello Parakeet non è scaricato: scaricalo da Altro › IA › Trascrizione."
            case .downloadIncompleto: "Download di Parakeet incompleto: riprova con una connessione stabile."
            case .danneggiato: "Il modello Parakeet è incompleto o danneggiato: scaricalo di nuovo da Altro › IA › Trascrizione."
            case .vuota: "Nessun parlato riconosciuto nella registrazione."
            }
        }
    }

    /// Trascrive in italiano leggendo il file a blocchi dal disco (memoria costante anche per lezioni di ore).
    @concurrent
    static func trascrivi(_ url: URL, durata: TimeInterval,
                          progresso: @escaping @Sendable (Double, String) -> Void) async throws -> String {
        guard installato else { throw Errore.nonInstallato }
        progresso(0, "Caricamento del modello…")
        let modelli: AsrModels
        do {
            modelli = try await AsrModels.load(from: cartella, version: versione)
        } catch {
            // File mancanti o rovinati: il modello si considera da riscaricare.
            try? FileManager.default.removeItem(at: conferma)
            throw Errore.danneggiato
        }
        let asr = AsrManager()
        try await asr.loadModels(modelli)
        let flusso = await asr.transcriptionProgressStream
        let osserva = Task {
            for try await p in flusso where durata > 0 {
                progresso(min(p, 0.99), faseTrascrizione(p * durata, di: durata))
            }
        }
        defer { osserva.cancel() }
        progresso(0, "Trascrizione…")
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

/// Segna (una volta) l'inizio della preparazione del modello, dopo il download.
private nonisolated final class InizioPreparazione: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Date?
    var inizio: Date? { lock.lock(); defer { lock.unlock() }; return data }
    func segna() { lock.lock(); if data == nil { data = Date() }; lock.unlock() }
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
