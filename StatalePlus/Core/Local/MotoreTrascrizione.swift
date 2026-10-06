import AVFoundation
import CoreML
import FluidAudio
import Foundation
import OSLog

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
        libera()
        try? FileManager.default.removeItem(at: cartella)
        try? FileManager.default.removeItem(at: conferma)
    }

    /// Il modello non si carica: va riscaricato.
    static func segnaDanneggiato() {
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

    /// Trascrive in italiano a blocchi di circa 10 minuti (`SegmentiAudio`), tagliati nel punto più silenzioso vicino al
    /// confine. Prima FluidAudio convertiva l'intera lezione in un file temporaneo prima di iniziare, senza avanzamento:
    /// su 2 h 25 min la barra restava ferma abbastanza perché iOS chiudesse l'attività di sistema (dopo circa 30 s
    /// senza avanzamento), e la trascrizione ripartiva da zero. A blocchi:
    /// - l'avanzamento si muove anche durante la preparazione dell'audio di ogni blocco (pochi secondi);
    /// - il testo di ogni blocco si salva in `Caches/TrascrizioniInCorso`: un lavoro interrotto riprende dal blocco
    ///   successivo invece che da capo;
    /// - il file temporaneo è di un blocco (circa 38 MB) invece che di tutta la lezione.
    @concurrent
    static func trascrivi(_ url: URL, durata: TimeInterval,
                          progresso: @escaping @Sendable (Double, String) -> Void) async throws -> TestoTrascritto {
        guard installato else { throw Errore.nonInstallato }
        progresso(0, "Caricamento del modello…")
        // Mentre il modello si carica (la prima volta dopo l'installazione anche qualche minuto) l'avanzamento si muove
        // un poco: con l'avanzamento fermo iOS considerava bloccata l'attività di sistema e la chiudeva ("non riuscita").
        let attesa = Task {
            var secondi = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                secondi += 2
                progresso(min(Self.quotaCaricamento, Double(secondi) * 0.0005),
                          secondi >= 10 ? "Preparazione del modello: la prima volta richiede qualche minuto" : "Caricamento del modello…")
            }
        }
        let (asr, condiviso): (AsrManager, condiviso: Bool)
        do {
            (asr, condiviso) = try await pronto.prendi()
            attesa.cancel()
            EsecuzioneEstesa.traccia("Parakeet pronto (condiviso: \(condiviso)), in primo piano: \(PrimoPiano.attivo)")
        } catch {
            attesa.cancel()
            EsecuzioneEstesa.traccia("Parakeet non caricato: \(String(describing: error))", errore: true)
            throw error
        }
        defer { Task { if condiviso { await pronto.restituisci() } else { await asr.cleanup() } } }

        let blocchi = try SegmentiAudio.piano(url)
        let totale = blocchi.last?.fine ?? durata
        let cartella = try SegmentiAudio.cartellaLavoro(per: url)
        let quota = Self.quotaCaricamento
        let n = Double(blocchi.count)
        var testi: [String] = []
        var ancore: [Ancora] = []
        // Secondi di lavoro per minuto di audio, misurati sui blocchi già fatti (prima stima prudente: 4 s/min; su
        // iPhone 17 Pro Max in background circa 3,6).
        var secondiLavoro: Double = 0
        var minutiFatti: Double = 0
        for (i, blocco) in blocchi.enumerated() {
            try Task.checkCancellation()
            let base = Double(i)
            let fatto = cartella.appending(path: "blocco-\(i).txt")
            let tempiBlocco = cartella.appending(path: "blocco-\(i).tempi.json")
            if let t = try? String(contentsOf: fatto, encoding: .utf8) {
                testi.append(t)
                ancore += (try? Data(contentsOf: tempiBlocco)).flatMap { try? JSONDecoder().decode([Ancora].self, from: $0) } ?? []
                progresso(quota + (base + 1) / n * (1 - quota), faseTrascrizione(blocco.fine, di: totale))
                continue
            }
            let audio = cartella.appending(path: "blocco-\(i).caf")
            defer { try? FileManager.default.removeItem(at: audio) }
            let inizioBlocco = Date()
            try SegmentiAudio.converti(url, blocco, in: audio) { f in
                progresso(quota + (base + f * 0.02) / n * (1 - quota),
                          "Preparazione dell'audio · " + faseTrascrizione(blocco.inizio, di: totale))
            }
            // L'avanzamento di FluidAudio conta i pezzi inviati al Neural Engine (4 in parallelo), non quelli finiti:
            // arriva quasi alla fine del blocco quando partono gli ultimi e poi resta fermo finché non finiscono (sul
            // telefono "Trascritti 40 di 145 min" fermo per mezzo minuto). Dentro il blocco l'avanzamento si stima
            // quindi dal tempo, con la velocità dei blocchi già fatti, e si aggiorna ogni secondo.
            let minutiBlocco = (blocco.fine - blocco.inizio) / 60
            let atteso = max(5, (minutiFatti > 0 ? secondiLavoro / minutiFatti : 4) * minutiBlocco)
            let inviati = AvanzamentoInviato()
            let riporta: @Sendable () -> Void = {
                let f = min(0.97, max(inviati.valore * 0.5, Date().timeIntervalSince(inizioBlocco) / atteso))
                progresso(quota + (base + 0.02 + f * 0.98) / n * (1 - quota),
                          faseTrascrizione(blocco.inizio + f * (blocco.fine - blocco.inizio), di: totale))
            }
            let flusso = await asr.transcriptionProgressStream
            let osserva = Task {
                for try await p in flusso { inviati.valore = min(max(p, 0), 1) }
            }
            let battito = Task {
                while !Task.isCancelled {
                    riporta()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            defer { osserva.cancel(); battito.cancel() }
            var stato = TdtDecoderState.make()
            let risultato: ASRResult
            do {
                risultato = try await asr.transcribe(audio, decoderState: &stato, language: .italian)
            } catch {
                EsecuzioneEstesa.traccia("Parakeet interrotto al blocco \(i + 1) di \(blocchi.count) (in primo piano: \(PrimoPiano.attivo)): \(String(describing: error))", errore: true)
                // Un modello caricato da tempo può non essere più valido (es. dopo il background): si ricarica la volta dopo.
                if condiviso, !(error is CancellationError) { await pronto.rilascia() }
                throw error
            }
            try Task.checkCancellation()
            secondiLavoro += Date().timeIntervalSince(inizioBlocco)
            minutiFatti += minutiBlocco
            let t = risultato.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Àncore del blocco dai tempi dei token, spostate all'inizio del blocco nella registrazione.
            let parole = buildWordTimings(from: risultato.tokenTimings ?? [])
                .map { (t: $0.startTime + blocco.inizio, parola: TempiTrascrizione.normalizza($0.word)) }
                .filter { !$0.parola.isEmpty }
            let ancoreBlocco = TempiTrascrizione.ancore(da: parole)
            if let dati = try? JSONEncoder().encode(ancoreBlocco) { try? dati.write(to: tempiBlocco) }
            try? t.write(to: fatto, atomically: true, encoding: .utf8)
            testi.append(t)
            ancore += ancoreBlocco
            EsecuzioneEstesa.traccia("Blocco \(i + 1) di \(blocchi.count) trascritto (\(t.count) caratteri), in primo piano: \(PrimoPiano.attivo)")
        }
        try? FileManager.default.removeItem(at: cartella)
        let testo = senzaRipetizioni(testi.filter { !$0.isEmpty }.joined(separator: " "))
        guard !testo.isEmpty else { throw Errore.vuota }
        return TestoTrascritto(testo: testo, ancore: ancore)
    }
}

/// Ultimo avanzamento comunicato da FluidAudio per il blocco in corso (letto dal battito di ogni secondo).
private nonisolated final class AvanzamentoInviato: @unchecked Sendable {
    private let lock = NSLock()
    private var p: Double = 0
    var valore: Double {
        get { lock.lock(); defer { lock.unlock() }; return p }
        set { lock.lock(); p = newValue; lock.unlock() }
    }
}

/// Divisione di una registrazione in blocchi per Parakeet e conversione di un blocco nel formato del modello
/// (16 kHz, mono, Float32), leggendo un secondo di audio alla volta.
nonisolated enum SegmentiAudio {
    struct Blocco: Sendable {
        let inizio: TimeInterval
        let fine: TimeInterval
    }

    enum Errore: LocalizedError {
        case conversione
        var errorDescription: String? { "Non è stato possibile preparare l'audio per la trascrizione." }
    }

    static let durataBlocco: TimeInterval = 600

    /// Blocchi di circa 10 minuti; i confini cadono nel punto più silenzioso entro 5 secondi, per non tagliare parole.
    /// Una registrazione fino a 15 minuti resta in un blocco solo.
    static func piano(_ url: URL) throws -> [Blocco] {
        let file = try AVAudioFile(forReading: url)
        let sr = file.processingFormat.sampleRate
        let totale = Double(file.length) / sr
        guard totale > durataBlocco * 1.5 else { return [Blocco(inizio: 0, fine: totale)] }
        var confini: [TimeInterval] = [0]
        var prossimo = durataBlocco
        while totale - prossimo > durataBlocco / 2 {
            let confine = puntoSilenzioso(file, vicino: prossimo) ?? prossimo
            confini.append(confine)
            prossimo = confine + durataBlocco
        }
        confini.append(totale)
        return zip(confini, confini.dropFirst()).map { Blocco(inizio: $0, fine: $1) }
    }

    /// Cartella dei blocchi di una registrazione: resta fra un tentativo e l'altro e si cancella a lavoro finito.
    static func cartellaLavoro(per url: URL) throws -> URL {
        let byte = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let nome = "\(url.deletingPathExtension().lastPathComponent)-\(byte)-\(Int(durataBlocco))"
        let cartella = URL.cachesDirectory.appending(path: "TrascrizioniInCorso/\(nome)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        return cartella
    }

    /// Centro della finestra di 50 ms più silenziosa fra 5 secondi prima e 5 secondi dopo `t`.
    private static func puntoSilenzioso(_ file: AVAudioFile, vicino t: TimeInterval) -> TimeInterval? {
        let sr = file.processingFormat.sampleRate
        let inizio = max(0, t - 5)
        let quanti = AVAudioFrameCount(10 * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: quanti) else { return nil }
        file.framePosition = AVAudioFramePosition(inizio * sr)
        guard (try? file.read(into: buffer, frameCount: quanti)) != nil, let canale = buffer.floatChannelData?[0] else { return nil }
        let finestra = max(1, Int(0.05 * sr))
        var migliore = (energia: Float.greatestFiniteMagnitude, indice: 0)
        var i = 0
        while i + finestra <= Int(buffer.frameLength) {
            var energia: Float = 0
            for k in i..<(i + finestra) { energia += canale[k] * canale[k] }
            if energia < migliore.energia { migliore = (energia, i) }
            i += finestra
        }
        return inizio + Double(migliore.indice + finestra / 2) / sr
    }

    /// Converte il blocco in un file CAF a 16 kHz mono Float32; `progresso` riceve 0…1 (circa una volta al secondo
    /// di lavoro, non a ogni buffer).
    static func converti(_ url: URL, _ blocco: Blocco, in destinazione: URL, progresso: (Double) -> Void) throws {
        let file = try AVAudioFile(forReading: url)
        let sr = file.processingFormat.sampleRate
        guard let formato = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let convertitore = AVAudioConverter(from: file.processingFormat, to: formato),
              let ingresso = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(sr)),
              let uscitaBuffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: 17_600) else { throw Errore.conversione }
        try? FileManager.default.removeItem(at: destinazione)
        let uscita = try AVAudioFile(forWriting: destinazione, settings: formato.settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        let primo = AVAudioFramePosition(blocco.inizio * sr)
        let ultimo = min(AVAudioFramePosition(blocco.fine * sr), file.length)
        file.framePosition = primo
        let lettore = LettoreBlocco(file: file, buffer: ingresso, fine: ultimo)
        var ultimoAvviso = Date.distantPast
        while true {
            try Task.checkCancellation()
            uscitaBuffer.frameLength = 0
            var errore: NSError?
            let stato = convertitore.convert(to: uscitaBuffer, error: &errore) { _, statoIngresso in
                lettore.prossimo(statoIngresso)
            }
            if let errore { throw errore }
            if uscitaBuffer.frameLength > 0 { try uscita.write(from: uscitaBuffer) }
            if Date().timeIntervalSince(ultimoAvviso) >= 1 {
                ultimoAvviso = Date()
                progresso(Double(file.framePosition - primo) / Double(max(ultimo - primo, 1)))
            }
            if stato == .endOfStream || stato == .error { break }
        }
        progresso(1)
    }

    /// Fornisce al convertitore un secondo di audio alla volta fino alla fine del blocco.
    private final class LettoreBlocco: @unchecked Sendable {
        let file: AVAudioFile
        let buffer: AVAudioPCMBuffer
        let fine: AVAudioFramePosition

        init(file: AVAudioFile, buffer: AVAudioPCMBuffer, fine: AVAudioFramePosition) {
            self.file = file
            self.buffer = buffer
            self.fine = fine
        }

        func prossimo(_ stato: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            let restanti = fine - file.framePosition
            guard restanti > 0,
                  (try? file.read(into: buffer, frameCount: min(buffer.frameCapacity, AVAudioFrameCount(restanti)))) != nil,
                  buffer.frameLength > 0 else {
                stato.pointee = .endOfStream
                return nil
            }
            stato.pointee = .haveData
            return buffer
        }
    }
}

nonisolated extension ParakeetLocale {
    /// Parte della barra dedicata al caricamento del modello.
    fileprivate static let quotaCaricamento = 0.03

    /// Il modello caricato, pronto per la prossima trascrizione.
    fileprivate static let pronto = ModelloPronto()

    /// Pre-riscaldamento: carica Parakeet sul Neural Engine in anticipo (all'inizio di una registrazione), così alla
    /// fine la trascrizione parte subito invece di attendere qualche secondo di caricamento. Il modello resta in
    /// memoria qualche minuto dopo l'ultima trascrizione, poi si libera.
    static func preriscalda() {
        guard installato, Preferenze.motoreTrascrizione == .parakeet else { return }
        Task.detached(priority: .utility) { try? await pronto.prepara() }
    }

    /// Alla prima apertura dopo un'installazione o un aggiornamento (anche da TestFlight) Core ML ricompila il modello
    /// per il Neural Engine, e può richiedere qualche minuto: lo si fa subito, con l'app in primo piano, invece che
    /// alla prima trascrizione (magari con l'app già in background).
    static func preparaDopoAggiornamento() {
        let versione = [Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"),
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")]
            .compactMap { $0 as? String }.joined(separator: "-")
        let chiave = "parakeetPreparatoPer"
        guard installato, UserDefaults.standard.string(forKey: chiave) != versione else { return }
        Task.detached(priority: .utility) {
            guard (try? await pronto.prepara()) != nil else { return }
            UserDefaults.standard.set(versione, forKey: chiave)
        }
    }

    /// Libera subito il modello (memoria scarsa).
    static func libera() {
        Task { await pronto.rilascia() }
    }
}

/// `AsrManager` con i modelli caricati, condiviso fra pre-riscaldamento e trascrizioni. FluidAudio segue
/// l'avanzamento di una trascrizione alla volta per manager: se è già occupato (due trascrizioni insieme) se ne
/// carica un altro solo per quella.
/// Il caricamento di Core ML non si può interrompere: chi lo aspetta però sì (`attendiAnnullabile`). Un caricamento
/// rimasto senza nessuno che lo aspetta finisce comunque, resta pronto per la volta dopo e si libera dopo tre minuti.
private actor ModelloPronto {
    private var asr: AsrManager?
    private var occupato = false
    private var caricamento: Task<AsrManager, Error>?
    private var rilascio: Task<Void, Never>?

    func prepara() async throws {
        _ = try await condiviso()
    }

    /// Il manager per una trascrizione; `condiviso` = da restituire con `restituisci()`.
    func prendi() async throws -> (AsrManager, condiviso: Bool) {
        if occupato {
            let separato = Task { try await Self.carica() }
            return (try await attendiAnnullabile(separato, alloAnnullo: { separato.cancel() }), false)
        }
        occupato = true
        do {
            return (try await condiviso(), true)
        } catch {
            occupato = false
            programmaRilascio()
            throw error
        }
    }

    /// Fine della trascrizione: il modello resta pronto per tre minuti, poi si libera.
    func restituisci() {
        occupato = false
        programmaRilascio()
    }

    func rilascia() {
        rilascio?.cancel()
        rilascio = nil
        if let asr, !occupato { Task { await asr.cleanup() } }
        asr = nil
    }

    private func programmaRilascio() {
        rilascio?.cancel()
        guard asr != nil, !occupato else { rilascio = nil; return }
        rilascio = Task {
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled else { return }
            rilascia()
        }
    }

    private func condiviso() async throws -> AsrManager {
        rilascio?.cancel()
        rilascio = nil
        if let asr { return asr }
        let compito: Task<AsrManager, Error>
        if let caricamento {
            compito = caricamento
        } else {
            compito = Task {
                do {
                    let nuovo = try await Self.carica()
                    await self.caricato(nuovo)
                    return nuovo
                } catch {
                    await self.caricamentoFallito()
                    throw error
                }
            }
            caricamento = compito
        }
        return try await attendiAnnullabile(compito)
    }

    private func caricato(_ nuovo: AsrManager) {
        asr = nuovo
        caricamento = nil
        programmaRilascio()
    }

    private func caricamentoFallito() { caricamento = nil }

    private static func carica() async throws -> AsrManager {
        let modelli: AsrModels
        do {
            modelli = try await AsrModels.load(from: ParakeetLocale.cartella, version: ParakeetLocale.versione)
        } catch {
            // File mancanti o rovinati: il modello si considera da riscaricare.
            ParakeetLocale.segnaDanneggiato()
            throw ParakeetLocale.Errore.danneggiato
        }
        let asr = AsrManager()
        try await asr.loadModels(modelli)
        return asr
    }
}

/// Aspetta il risultato di un `Task` smettendo subito di aspettare se chi attende viene annullato (lanciando
/// `CancellationError`); il `Task` prosegue, salvo che `alloAnnullo` lo fermi.
nonisolated func attendiAnnullabile<T: Sendable>(_ compito: Task<T, Error>,
                                                 alloAnnullo: @escaping @Sendable () -> Void = {}) async throws -> T {
    let attesa = AttesaUnica<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            attesa.imposta(c)
            Task { attesa.concludi(await compito.result) }
        }
    } onCancel: {
        alloAnnullo()
        attesa.concludi(.failure(CancellationError()))
    }
}

/// Continuazione ripresa una sola volta, dal primo fra risultato e annullamento.
private nonisolated final class AttesaUnica<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuazione: CheckedContinuation<T, Error>?
    private var anticipato: Result<T, Error>?

    func imposta(_ c: CheckedContinuation<T, Error>) {
        lock.lock()
        if let anticipato {
            self.anticipato = nil
            lock.unlock()
            c.resume(with: anticipato)
            return
        }
        continuazione = c
        lock.unlock()
    }

    func concludi(_ r: Result<T, Error>) {
        lock.lock()
        guard let c = continuazione else {
            // Annullato prima che la continuazione esistesse: la si riprende appena arriva.
            if anticipato == nil { anticipato = r }
            lock.unlock()
            return
        }
        continuazione = nil
        lock.unlock()
        c.resume(with: r)
    }
}

/// Segna (una volta) l'inizio della preparazione del modello, dopo il download.
private nonisolated final class InizioPreparazione: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Date?
    var inizio: Date? { lock.lock(); defer { lock.unlock() }; return data }
    func segna() { lock.lock(); if data == nil { data = Date() }; lock.unlock() }
}

/// Ripulitura dei modelli non più usati:
/// - Whisper, sostituito da Parakeet (più lento, su audio registrato da lontano inventava frasi): circa 630 MB;
/// - Qwen 3.5 4B, sostituito da Apple Intelligence per riassunti e glossario (su iPhone 17 Pro Max il glossario
///   richiedeva 6-7 minuti e il 6% di batteria): circa 3 GB.
nonisolated enum ModelliDismessi {
    static func elimina() {
        let fm = FileManager.default
        let base = ScaricatoreModelli.cartellaBase
        try? fm.removeItem(at: base.appending(path: "qwen3.5-4b-4bit", directoryHint: .isDirectory))
        try? fm.removeItem(at: base.appending(path: "installato-qwen3.5-4b-4bit"))
        if UserDefaults.standard.string(forKey: "motoreRiassunto") == "qwen" {
            UserDefaults.standard.removeObject(forKey: "motoreRiassunto")
        }
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
