import AVFoundation
import Observation

// MARK: - Modello

/// Registrazione vocale di una lezione. Indice in `Registrazioni/registrazioni.json`, audio `<id>.m4a` accanto.
nonisolated struct Registrazione: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var titolo: String
    var codiceInsegnamento: String?   // "DBD-28_1"
    var insegnamento: String?         // "Colloquio e processo anamnestico in neuropsicologia"
    let creata: Date
    var durata: TimeInterval
    let file: String                  // "<id>.m4a"
    var segnalibri: [TimeInterval]
    var note: String
    var trascrittaIl: Date? = nil       // testo in `<id>.txt` (Speech, modificabile)
    var riassuntoIl: Date? = nil        // Markdown in `<id>.riassunto.md` (Apple Intelligence)
}

// MARK: - Archivio

@Observable
final class RecordingStore {
    private(set) var items: [Registrazione] = []
    let folder: URL
    private var db: URL { folder.appending(path: "registrazioni.json") }

    init() {
        folder = URL.applicationSupportDirectory.appending(path: "Registrazioni", directoryHint: .isDirectory)
        // Accessibile a schermo bloccato dopo il primo sblocco: la registrazione continua in background.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        if let data = try? Data(contentsOf: db), let list = try? JSONDecoder().decode([Registrazione].self, from: data) {
            items = list.filter { FileManager.default.fileExists(atPath: url(for: $0).path(percentEncoded: false)) }
        }
    }

    func url(for r: Registrazione) -> URL { folder.appending(path: r.file) }
    private func trascrizioneURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).txt") }
    private func riassuntoURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).riassunto.md") }

    func item(_ id: UUID) -> Registrazione? { items.first { $0.id == id } }

    // MARK: Trascrizione e riassunto (file separati dall'indice)

    func trascrizione(_ id: UUID) -> String? { try? String(contentsOf: trascrizioneURL(id), encoding: .utf8) }
    func riassunto(_ id: UUID) -> String? { try? String(contentsOf: riassuntoURL(id), encoding: .utf8) }

    func salvaTrascrizione(_ id: UUID, _ testo: String?) {
        scrivi(testo, trascrizioneURL(id))
        guard var r = item(id) else { return }
        r.trascrittaIl = testo == nil ? nil : .now
        update(r)
    }

    func salvaRiassunto(_ id: UUID, _ testo: String?) {
        scrivi(testo, riassuntoURL(id))
        guard var r = item(id) else { return }
        r.riassuntoIl = testo == nil ? nil : .now
        update(r)
    }

    private func scrivi(_ testo: String?, _ url: URL) {
        if let testo {
            try? Data(testo.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func add(_ r: Registrazione) { items.insert(r, at: 0); save() }

    func update(_ r: Registrazione) {
        guard let i = items.firstIndex(where: { $0.id == r.id }) else { return }
        items[i] = r
        save()
    }

    func delete(_ r: Registrazione) {
        try? FileManager.default.removeItem(at: url(for: r))
        try? FileManager.default.removeItem(at: trascrizioneURL(r.id))
        try? FileManager.default.removeItem(at: riassuntoURL(r.id))
        items.removeAll { $0.id == r.id }
        save()
    }

    /// Elimina tutte le registrazioni e l'indice.
    func deleteAll() {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .forEach { try? FileManager.default.removeItem(at: $0) }
        items = []
        save()
    }

    var spazioOccupato: Int64 {
        items.reduce(0) { acc, r in
            acc + ((try? FileManager.default.attributesOfItem(atPath: url(for: r).path(percentEncoded: false))[.size] as? Int64) ?? 0)
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(items) else { return }
        try? data.write(to: db, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - Registratore

@Observable
final class AudioRecorder {
    enum State { case idle, recording, paused }

    private(set) var state: State = .idle
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var segnalibri: [TimeInterval] = []
    private(set) var insegnamento: InsegnamentoAgenda?
    var error: String?

    private var recorder: AVAudioRecorder?
    private var id = UUID()
    private var startedAt = Date.now
    private var meterTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    func start(in store: RecordingStore, insegnamento: InsegnamentoAgenda?) async {
        guard state == .idle else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Consenti l'accesso al microfono da Impostazioni › Statale+."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            id = UUID()
            let url = store.folder.appending(path: "\(id.uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = r
            self.insegnamento = insegnamento
            segnalibri = []
            elapsed = 0
            startedAt = .now
            state = .recording
            error = nil
            observeInterruptions()
            startMeter()
        } catch {
            self.error = "Impossibile avviare la registrazione: \(error.localizedDescription)"
        }
    }

    func pause() { recorder?.pause(); state = .paused }

    func resume() {
        try? AVAudioSession.sharedInstance().setActive(true)
        if recorder?.record() == true { state = .recording }
    }

    func bookmark() { segnalibri.append(recorder?.currentTime ?? elapsed) }

    /// Chiude il file e restituisce la registrazione da salvare.
    func stop() -> Registrazione? {
        guard let r = recorder else { return nil }
        let durata = r.currentTime
        r.stop()
        cleanup()
        let titolo = insegnamento.map { "\($0.nome) – \(startedAt.formatted(date: .abbreviated, time: .omitted))" }
            ?? "Registrazione del \(startedAt.formatted(date: .abbreviated, time: .shortened))"
        return Registrazione(id: id, titolo: titolo, codiceInsegnamento: insegnamento?.codice, insegnamento: insegnamento?.nome,
                             creata: startedAt, durata: durata, file: "\(id.uuidString).m4a", segnalibri: segnalibri, note: "")
    }

    func discard() {
        recorder?.stop()
        recorder?.deleteRecording()
        cleanup()
    }

    private func cleanup() {
        meterTask?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        recorder = nil
        state = .idle
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
                let db = r.averagePower(forChannel: 0)                 // -160…0 dB
                self.level = self.state == .recording ? max(0, min(1, (db + 50) / 50)) : 0
                self.elapsed = r.currentTime
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Telefonate e altre interruzioni mettono in pausa; alla fine si riprende se il sistema lo consente.
    private func observeInterruptions() {
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let opts = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init) ?? []
            MainActor.assumeIsolated {
                guard let self, self.state != .idle else { return }
                if type == .began { self.state = .paused }
                else if type == .ended, opts.contains(.shouldResume) { self.resume() }
            }
        }
    }
}

// MARK: - Player

@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1
    private var player: AVAudioPlayer?
    private var tick: Task<Void, Never>?

    func load(_ url: URL) {
        guard player?.url != url else { return }
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        currentTime = 0
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.rate = rate
        player.play()
        isPlaying = true
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
                if !p.isPlaying { self.isPlaying = false; return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func pause() { player?.pause(); isPlaying = false; tick?.cancel() }

    func seek(to t: TimeInterval) {
        let v = max(0, min(duration, t))
        player?.currentTime = v
        currentTime = v
    }

    func skip(_ delta: TimeInterval) { seek(to: currentTime + delta) }

    func setRate(_ r: Float) { rate = r; player?.rate = r }

    func stop() {
        player?.stop()
        tick?.cancel()
        isPlaying = false
        player = nil
    }
}
