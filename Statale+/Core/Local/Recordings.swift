import AVFoundation
import Observation
import os

// MARK: - Modello

/// Registrazione vocale di una lezione. Per ogni registrazione, nella cartella `Registrazioni/`:
/// - `<id>.m4a` audio;
/// - `<id>.json` metadati (questa struttura), scritti all'avvio della registrazione e a ogni modifica;
/// - `<id>.txt` trascrizione e `<id>.riassunto.md` riassunto, se presenti;
/// - `<id>.originale.m4a` l'audio così come registrato, quando `<id>.m4a` è la versione migliorata.
/// `registrazioni.json` è l'indice di tutte; se si perde o non è allineato, all'avvio si ricostruisce dai file.
nonisolated struct Registrazione: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var titolo: String
    var codiceInsegnamento: String?   // "DBD-28_1"
    var insegnamento: String?         // "Colloquio e processo anamnestico in neuropsicologia"
    var creata: Date
    var durata: TimeInterval
    let file: String                  // "<id>.m4a"
    var segnalibri: [TimeInterval]
    var note: String
    var trascrittaIl: Date? = nil       // testo in `<id>.txt` (Speech, modificabile)
    var riassuntoIl: Date? = nil        // Markdown in `<id>.riassunto.md` (Apple Intelligence)
    /// Metadati scritti all'avvio: la registrazione non è stata chiusa regolarmente (app chiusa durante la registrazione).
    var inCorso: Bool? = nil
    /// Ricostruita dai file durante la riconciliazione: data, ora e insegnamento vanno confermati dall'utente.
    var daVerificare: Bool? = nil
    /// `<id>.m4a` è la versione migliorata (volume, rumore di fondo); l'originale è in `<id>.originale.m4a`.
    var migliorata: Bool? = nil

    var richiedeVerifica: Bool { daVerificare == true }

    /// "Colloquio e processo anamnestico – 30 set 2026" oppure "Registrazione del 30 set 2026, 10:15".
    static func titoloPredefinito(insegnamento: String?, creata: Date) -> String {
        insegnamento.map { "\($0) – \(creata.italiano(date: .abbreviated, time: .omitted))" }
            ?? "Registrazione del \(creata.italiano(date: .abbreviated, time: .shortened))"
    }

    /// Nome del file quando si condivide l'audio: "Colloquio e processo anamnestico – 30 set 2026, ore 10.15".
    /// Sul dispositivo i file restano `<id>.m4a` (indice, recupero, trascrizioni e riassunti si basano sull'id);
    /// il nome leggibile si calcola al momento, quindi vale anche per le registrazioni già fatte e segue il titolo.
    var nomeCondivisione: String {
        let data = creata.italiano(date: .abbreviated, time: .omitted)
        let ora = creata.italiano(date: .omitted, time: .shortened)
        var nome = titolo.trimmingCharacters(in: .whitespacesAndNewlines)
        if nome.isEmpty { nome = "Registrazione" }
        if !nome.contains(data) { nome += " – \(data)" }
        if !nome.contains(ora) { nome += ", ore \(ora)" }
        // I due punti e le barre non sono ammessi (o danno problemi) nei nomi di file.
        nome = nome.replacingOccurrences(of: ":", with: ".")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(nome.prefix(150))
    }
}

// MARK: - Archivio

@Observable
final class RecordingStore {
    private(set) var items: [Registrazione] = []
    /// Registrazioni recuperate dai file all'ultimo avvio (per l'avviso all'utente).
    private(set) var recuperate: [UUID] = []
    /// Ultimo errore di scrittura o eliminazione, mostrato in fondo alla schermata Registrazioni.
    private(set) var ultimoErrore: String?
    let folder: URL
    @ObservationIgnored private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Statale+", category: "registrazioni")
    private var db: URL { folder.appending(path: "registrazioni.json") }

    /// Stesso formato in scrittura e in lettura. Le date si leggono sia come ISO 8601 sia come numero
    /// (prima di questa versione l'indice era scritto in ISO 8601 ma letto come numero: all'avvio la lettura
    /// falliva, la lista risultava vuota e il salvataggio successivo scriveva `[]`).
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let n = try? c.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: n) }
            let s = try c.decode(String.self)
            let f = ISO8601DateFormatter()
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Data non valida: \(s)")
        }
        return d
    }()

    init() {
        folder = URL.applicationSupportDirectory.appending(path: "Registrazioni", directoryHint: .isDirectory)
        // Accessibile a schermo bloccato dopo il primo sblocco: la registrazione continua in background.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        if let data = try? Data(contentsOf: db) {
            do { items = try Self.decoder.decode([Registrazione].self, from: data) } catch {
                log.error("Indice registrazioni illeggibile: \(error.localizedDescription, privacy: .public)")
            }
        }
        riconcilia()
    }

    func url(for r: Registrazione) -> URL { folder.appending(path: r.file) }
    private func audioURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).m4a") }
    private func metadatiURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).json") }
    private func trascrizioneURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).txt") }
    private func riassuntoURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).riassunto.md") }
    private func originaleURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).originale.m4a") }
    private func temporaneoURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).migliorata.tmp.m4a") }
    private func fileCollegati(_ id: UUID) -> [URL] {
        [audioURL(id), metadatiURL(id), trascrizioneURL(id), riassuntoURL(id), originaleURL(id), temporaneoURL(id)]
    }
    private func esiste(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    // MARK: Miglioramento dell'audio

    func haOriginale(_ id: UUID) -> Bool { esiste(originaleURL(id)) }

    /// Audio da trascrivere: sempre l'originale. Nelle prove il miglioramento non aiuta Apple e Parakeet (con Apple
    /// i termini riconosciuti scendono da 197 a 180) e serve solo all'ascolto.
    func audioPerTrascrizione(_ r: Registrazione) -> URL {
        esiste(originaleURL(r.id)) ? originaleURL(r.id) : url(for: r)
    }

    /// Migliora l'audio partendo sempre dall'originale (rifarlo non accumula elaborazioni). La versione nuova si scrive
    /// in un file temporaneo e sostituisce `<id>.m4a` solo a elaborazione finita; l'originale si conserva.
    func migliora(_ id: UUID, progresso: @escaping @Sendable (Double) -> Void) async throws {
        guard let r = item(id) else { return }
        let originale = originaleURL(id), temp = temporaneoURL(id)
        let sorgente = esiste(originale) ? originale : url(for: r)
        do {
            try await MiglioramentoAudio.migliora(sorgente, in: temp, progresso: progresso)
        } catch {
            rimuovi(temp)
            throw error
        }
        // Eliminata durante l'elaborazione: si butta il risultato.
        guard var attuale = item(id) else { rimuovi(temp); return }
        let fm = FileManager.default
        do {
            if !esiste(originale) {
                try fm.moveItem(at: url(for: attuale), to: originale)
            } else {
                rimuovi(url(for: attuale))
            }
            try fm.moveItem(at: temp, to: url(for: attuale))
        } catch {
            // Mai lasciare la registrazione senza audio.
            if !esiste(url(for: attuale)), esiste(originale) { try? fm.moveItem(at: originale, to: url(for: attuale)) }
            rimuovi(temp)
            segnala("Sostituzione dell'audio migliorato non riuscita: \(error.localizedDescription)")
            throw error
        }
        attuale.migliorata = true
        update(attuale)
    }

    /// Torna all'audio così come registrato ed elimina la versione migliorata.
    func ripristinaOriginale(_ id: UUID) {
        guard var r = item(id), esiste(originaleURL(id)) else { return }
        rimuovi(url(for: r))
        do { try FileManager.default.moveItem(at: originaleURL(id), to: url(for: r)) } catch {
            segnala("Ripristino dell'originale non riuscito: \(error.localizedDescription)")
            return
        }
        r.migliorata = nil
        update(r)
    }

    func item(_ id: UUID) -> Registrazione? { items.first { $0.id == id } }

    // MARK: Trascrizione e riassunto (file separati dall'indice)

    func trascrizione(_ id: UUID) -> String? { try? String(contentsOf: trascrizioneURL(id), encoding: .utf8) }
    func riassunto(_ id: UUID) -> String? { try? String(contentsOf: riassuntoURL(id), encoding: .utf8) }

    /// Non scrive nulla se la registrazione nel frattempo è stata eliminata (elaborazione finita dopo l'eliminazione).
    func salvaTrascrizione(_ id: UUID, _ testo: String?) {
        guard var r = item(id) else { return }
        scrivi(testo, trascrizioneURL(id))
        r.trascrittaIl = testo == nil ? nil : .now
        update(r)
    }

    func salvaRiassunto(_ id: UUID, _ testo: String?) {
        guard var r = item(id) else { return }
        scrivi(testo, riassuntoURL(id))
        r.riassuntoIl = testo == nil ? nil : .now
        update(r)
    }

    private func scrivi(_ testo: String?, _ url: URL) {
        if let testo {
            scriviDati(Data(testo.utf8), url)
        } else {
            rimuovi(url)
        }
    }

    // MARK: Modifiche

    /// Metadati provvisori all'avvio della registrazione: se l'app viene chiusa prima dello stop,
    /// al lancio successivo data, ora e insegnamento si recuperano da qui.
    func iniziata(_ r: Registrazione) {
        var provvisoria = r
        provvisoria.inCorso = true
        scriviMetadati(provvisoria)
    }

    func add(_ r: Registrazione) {
        items.removeAll { $0.id == r.id }
        items.insert(r, at: 0)
        scriviMetadati(r)
        save()
    }

    func update(_ r: Registrazione) {
        guard let i = items.firstIndex(where: { $0.id == r.id }) else { return }
        items[i] = r
        scriviMetadati(r)
        save()
    }

    /// Conferma i dati di una registrazione ricostruita.
    func confermaVerifica(_ id: UUID) {
        guard var r = item(id) else { return }
        r.daVerificare = nil
        update(r)
        recuperate.removeAll { $0 == id }
    }

    /// Elimina audio, metadati, trascrizione, riassunto e la voce dell'indice.
    func delete(_ r: Registrazione) {
        fileCollegati(r.id).forEach(rimuovi)
        if r.file != "\(r.id.uuidString).m4a" { rimuovi(url(for: r)) }
        items.removeAll { $0.id == r.id }
        recuperate.removeAll { $0 == r.id }
        save()
    }

    /// Registrazione annullata dal registratore: via audio e metadati provvisori (non era nell'indice).
    func scartata(_ id: UUID) {
        fileCollegati(id).forEach(rimuovi)
    }

    /// Elimina tutte le registrazioni e l'indice.
    func deleteAll() {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.forEach(rimuovi)
        items = []
        recuperate = []
        save()
    }

    var spazioOccupato: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    // MARK: Riconciliazione

    /// Allinea indice e file:
    /// - audio senza voce nell'indice → recuperato dai metadati `<id>.json` o, per le versioni precedenti che non li
    ///   avevano, ricostruito dalle date del file (creazione = inizio, modifica = fine) e segnato "da verificare";
    /// - voce nell'indice senza audio → rimossa;
    /// - trascrizioni, riassunti e metadati rimasti senza audio → eliminati;
    /// - metadati mancanti o non aggiornati → riscritti.
    /// `escludi`: registrazione in corso, da non toccare.
    func riconcilia(escludi: UUID? = nil) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        // Miglioramento interrotto: via i temporanei; se manca l'audio ma c'è l'originale, si rimette a posto.
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let nome = url.lastPathComponent
            guard let id = UUID(uuidString: String(nome.prefix(36))), id != escludi else { continue }
            if nome.hasSuffix(".migliorata.tmp.m4a") { rimuovi(url) }
            if nome.hasSuffix(".originale.m4a"), !esiste(audioURL(id)) { try? fm.moveItem(at: url, to: audioURL(id)) }
        }
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let perId = Dictionary(grouping: files.compactMap { url -> (UUID, URL)? in
            guard let id = UUID(uuidString: String(url.lastPathComponent.prefix(36))) else { return nil }
            return (id, url)
        }, by: \.0).mapValues { $0.map(\.1) }

        var cambiato = false
        var nuove: [UUID] = []

        // Voci senza audio.
        let senzaAudio = items.filter { $0.id != escludi && !fm.fileExists(atPath: url(for: $0).path(percentEncoded: false)) }
        for r in senzaAudio {
            log.notice("Voce senza audio rimossa dall'indice: \(r.id.uuidString, privacy: .public)")
            fileCollegati(r.id).forEach(rimuovi)
            items.removeAll { $0.id == r.id }
            cambiato = true
        }

        for (id, urls) in perId where id != escludi {
            let audio = audioURL(id)
            guard urls.contains(where: { $0.lastPathComponent == audio.lastPathComponent }) else {
                // File rimasti da un'eliminazione non completata.
                log.notice("File senza audio eliminati: \(id.uuidString, privacy: .public)")
                urls.forEach(rimuovi)
                continue
            }
            var r: Registrazione
            if let esistente = item(id) {
                r = esistente
            } else if let meta = leggiMetadati(id) {
                r = meta
                if r.inCorso == true {
                    // Chiusa senza stop (app terminata durante la registrazione). Un m4a non chiuso di solito non
                    // è leggibile: in quel caso la durata si stima dalle date e la registrazione va verificata.
                    let letta = durataAudio(audio)
                    r.durata = letta ?? max(0, dataModifica(audio).map { $0.timeIntervalSince(r.creata) } ?? 0)
                    if letta == nil { r.daVerificare = true }
                    r.inCorso = nil
                }
                nuove.append(id)
            } else {
                r = ricostruisci(id, audio: audio)
                nuove.append(id)
            }
            // Trascrizione e riassunto: le date seguono la presenza dei file.
            let tx = trascrizioneURL(id), md = riassuntoURL(id)
            let haTx = fm.fileExists(atPath: tx.path(percentEncoded: false))
            let haMd = fm.fileExists(atPath: md.path(percentEncoded: false))
            if haTx != (r.trascrittaIl != nil) { r.trascrittaIl = haTx ? (dataModifica(tx) ?? .now) : nil }
            if haMd != (r.riassuntoIl != nil) { r.riassuntoIl = haMd ? (dataModifica(md) ?? .now) : nil }
            r.migliorata = esiste(originaleURL(id)) ? true : nil

            if let i = items.firstIndex(where: { $0.id == id }) {
                if items[i] != r { items[i] = r; cambiato = true }
            } else {
                items.append(r)
                cambiato = true
            }
            if leggiMetadati(id) != r { scriviMetadati(r) }
        }

        if !nuove.isEmpty {
            log.notice("Registrazioni recuperate dai file: \(nuove.count, privacy: .public)")
            recuperate = nuove
        }
        if cambiato {
            items.sort { $0.creata > $1.creata }
            save()
        }
    }

    /// Registrazione senza metadati (versioni precedenti): data e durata dal file audio.
    private func ricostruisci(_ id: UUID, audio: URL) -> Registrazione {
        let fine = dataModifica(audio)
        let durata = durataAudio(audio) ?? max(0, (fine ?? .now).timeIntervalSince(dataCreazione(audio) ?? fine ?? .now))
        let creata = dataCreazione(audio) ?? fine.map { $0.addingTimeInterval(-durata) } ?? .now
        return Registrazione(id: id, titolo: Registrazione.titoloPredefinito(insegnamento: nil, creata: creata),
                             codiceInsegnamento: nil, insegnamento: nil, creata: creata, durata: durata,
                             file: audio.lastPathComponent, segnalibri: [], note: "", daVerificare: true)
    }

    private func durataAudio(_ url: URL) -> TimeInterval? {
        guard let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0 else { return nil }
        let d = Double(f.length) / f.fileFormat.sampleRate
        return d.isFinite && d > 0 ? d : nil
    }

    private func dataCreazione(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.creationDateKey]).creationDate }
    private func dataModifica(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }

    // MARK: File

    private func leggiMetadati(_ id: UUID) -> Registrazione? {
        guard let data = try? Data(contentsOf: metadatiURL(id)) else { return nil }
        return try? Self.decoder.decode(Registrazione.self, from: data)
    }

    private func scriviMetadati(_ r: Registrazione) {
        do { scriviDati(try Self.encoder.encode(r), metadatiURL(r.id)) } catch {
            segnala("Metadati non scritti per \(r.id.uuidString): \(error.localizedDescription)")
        }
    }

    private func scriviDati(_ data: Data, _ url: URL) {
        do { try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) } catch {
            segnala("Scrittura di \(url.lastPathComponent) non riuscita: \(error.localizedDescription)")
        }
    }

    /// Rimuove il file se esiste; ogni altro errore viene segnalato (non più ignorato).
    private func rimuovi(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do { try FileManager.default.removeItem(at: url) } catch {
            segnala("Eliminazione di \(url.lastPathComponent) non riuscita: \(error.localizedDescription)")
        }
    }

    private func segnala(_ messaggio: String) {
        log.error("\(messaggio, privacy: .public)")
        ultimoErrore = messaggio
    }

    private func save() {
        do { scriviDati(try Self.encoder.encode(items), db) } catch {
            segnala("Indice registrazioni non scritto: \(error.localizedDescription)")
        }
    }
}

// MARK: - Motore audio

/// Tutto ciò che tocca `AVAudioSession` gira qui, fuori dal main thread e un'operazione alla volta:
/// configurazione e attivazione della sessione, ma anche `record()`, `pause()`, `stop()` di `AVAudioRecorder` e
/// `play()`/`stop()` di `AVAudioPlayer`, che attivano o disattivano la sessione da soli in modo sincrono.
/// Le API di attivazione asincrone esistono solo da iOS 27; il target è iOS 17.
/// Le classi osservabili (`AudioRecorder`, `AudioPlayer`) tengono solo lo stato mostrato e chiedono qui il resto.
actor MotoreAudio {
    static let shared = MotoreAudio()

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var playerToken: UUID?

    // MARK: Registrazione

    func avviaRegistrazione(url: URL) throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try s.setActive(true)
        // Il microfono dell'iPhone di solito non espone il guadagno; dove si può, al massimo (lezioni registrate da lontano).
        if s.isInputGainSettable { try? s.setInputGain(1) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        guard r.record() else {
            try? s.setActive(false, options: .notifyOthersOnDeactivation)
            throw CocoaError(.fileWriteUnknown)
        }
        recorder = r
    }

    func pausaRegistrazione() { recorder?.pause() }

    func riprendiRegistrazione() -> Bool {
        guard let r = recorder else { return false }
        try? AVAudioSession.sharedInstance().setActive(true)
        return r.record()
    }

    /// Chiude il file (o lo elimina) e restituisce la durata registrata.
    func fermaRegistrazione(elimina: Bool) -> TimeInterval {
        guard let r = recorder else { return 0 }
        let durata = r.currentTime
        r.stop()
        if elimina { r.deleteRecording() }
        recorder = nil
        disattiva()
        return durata
    }

    /// Livello (dB, -160…0) e tempo trascorso, per il misuratore.
    func misura() -> (decibel: Float, tempo: TimeInterval)? {
        guard let r = recorder else { return nil }
        r.updateMeters()
        return (r.averagePower(forChannel: 0), r.currentTime)
    }

    // MARK: Riproduzione

    /// Apre il file e ne restituisce la durata (nil se non leggibile). Il token identifica il player che lo ha chiesto.
    func carica(_ url: URL, token: UUID) -> TimeInterval? {
        player?.stop()
        playerToken = token
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        return player?.duration
    }

    func riproduci(token: UUID, da tempo: TimeInterval, velocità: Float) -> Bool {
        guard token == playerToken, let p = player else { return false }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio)
        try? s.setActive(true)
        p.currentTime = tempo
        p.rate = velocità
        return p.play()
    }

    func pausa(token: UUID) {
        guard token == playerToken else { return }
        player?.pause()
    }

    func posizione(token: UUID) -> (tempo: TimeInterval, inRiproduzione: Bool)? {
        guard token == playerToken, let p = player else { return nil }
        return (p.currentTime, p.isPlaying)
    }

    func vai(token: UUID, a tempo: TimeInterval) {
        guard token == playerToken else { return }
        player?.currentTime = tempo
    }

    func velocità(token: UUID, _ v: Float) {
        guard token == playerToken else { return }
        player?.rate = v
    }

    func chiudi(token: UUID) {
        guard token == playerToken else { return }
        player?.stop()
        player = nil
        playerToken = nil
        if recorder == nil { disattiva() }
    }

    private func disattiva() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Registratore

@Observable
final class AudioRecorder {
    enum State { case idle, starting, recording, paused }

    private(set) var state: State = .idle
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var segnalibri: [TimeInterval] = []
    private(set) var insegnamento: InsegnamentoAgenda?
    var error: String?

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
        guard state == .idle else { return }
        state = .starting
        id = UUID()
        let url = store.folder.appending(path: "\(id.uuidString).m4a")
        do {
            try await MotoreAudio.shared.avviaRegistrazione(url: url)
            self.insegnamento = insegnamento
            segnalibri = []
            elapsed = 0
            startedAt = .now
            store.iniziata(bozza(durata: 0))
            state = .recording
            error = nil
            observeInterruptions()
            startMeter()
        } catch {
            state = .idle
            self.error = "Impossibile avviare la registrazione: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        Task { await MotoreAudio.shared.pausaRegistrazione() }
    }

    func resume() {
        guard state == .paused else { return }
        Task {
            let ok = await MotoreAudio.shared.riprendiRegistrazione()
            if ok, state == .paused { state = .recording }
        }
    }

    func bookmark() { segnalibri.append(elapsed) }

    /// Chiude il file e restituisce la registrazione da salvare.
    func stop() async -> Registrazione? {
        guard state == .recording || state == .paused else { return nil }
        let bozzaFinale = bozza(durata: elapsed)
        cleanup()
        let durata = await MotoreAudio.shared.fermaRegistrazione(elimina: false)
        var r = bozzaFinale
        if durata > 0 { r.durata = durata }
        return r
    }

    /// Id della registrazione in corso (esclusa dalla riconciliazione).
    var idInCorso: UUID? { state == .idle ? nil : id }

    private func bozza(durata: TimeInterval) -> Registrazione {
        Registrazione(id: id, titolo: Registrazione.titoloPredefinito(insegnamento: insegnamento?.nome, creata: startedAt),
                      codiceInsegnamento: insegnamento?.codice, insegnamento: insegnamento?.nome,
                      creata: startedAt, durata: durata, file: "\(id.uuidString).m4a", segnalibri: segnalibri, note: "")
    }

    func discard(in store: RecordingStore) {
        guard state != .idle else { return }
        let scartata = id
        cleanup()
        Task {
            _ = await MotoreAudio.shared.fermaRegistrazione(elimina: true)
            store.scartata(scartata)
        }
    }

    private func cleanup() {
        meterTask?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        state = .idle
        level = 0
    }

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let m = await MotoreAudio.shared.misura(), let self, !Task.isCancelled else { return }
                self.level = self.state == .recording ? max(0, min(1, (m.decibel + 50) / 50)) : 0
                self.elapsed = m.tempo
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
                guard let self, self.state == .recording || self.state == .paused else { return }
                if type == .began { self.state = .paused }
                else if type == .ended, opts.contains(.shouldResume) { self.resume() }
            }
        }
    }
}

// MARK: - Player

/// Stato del player mostrato nel dettaglio; l'`AVAudioPlayer` vero sta in `MotoreAudio`.
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1
    /// File presente ma non apribile (es. registrazione interrotta prima della chiusura del file).
    private(set) var illeggibile = false
    private var url: URL?
    private var token: UUID?
    private var tick: Task<Void, Never>?

    func load(_ url: URL) {
        guard self.url != url else { return }
        ricarica(url)
    }

    /// Riapre il file anche se l'URL è lo stesso (es. audio sostituito dalla versione migliorata).
    func ricarica(_ url: URL) {
        stop()
        self.url = url
        ultimoURL = url
        let t = UUID()
        token = t
        Task {
            let d = await MotoreAudio.shared.carica(url, token: t)
            guard token == t else { return }
            illeggibile = d == nil
            duration = d ?? 0
            currentTime = 0
        }
    }

    func toggle() { isPlaying ? pause() : play() }

    /// Schermate (trascrizione, riassunto) aperte sopra il dettaglio che usano questo player: finché ce n'è una,
    /// uscire dal dettaglio non ferma l'audio.
    var utilizzatori = 0
    /// Ultimo file caricato, per riaprirlo se il player è stato chiuso.
    private var ultimoURL: URL?

    /// Ferma e chiude l'audio poco dopo, se nel frattempo nessuna schermata lo sta usando.
    func chiudiSeInutilizzato() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if utilizzatori == 0 { stop() }
        }
    }

    func play() {
        // Chiuso (es. uscendo dal dettaglio): si riapre il file e si riparte dal punto in cui era.
        if token == nil, let u = ultimoURL, !illeggibile {
            let t = UUID(), da = currentTime
            token = t
            url = u
            isPlaying = true
            Task {
                guard await MotoreAudio.shared.carica(u, token: t) != nil, token == t else { isPlaying = false; return }
                let ok = await MotoreAudio.shared.riproduci(token: t, da: da, velocità: rate)
                guard token == t, isPlaying else { return }
                if ok { avviaTick(t) } else { isPlaying = false }
            }
            return
        }
        guard let t = token, !isPlaying, !illeggibile else { return }
        isPlaying = true
        let da = currentTime >= duration - 0.2 ? 0 : currentTime
        Task {
            let ok = await MotoreAudio.shared.riproduci(token: t, da: da, velocità: rate)
            guard token == t, isPlaying else { return }
            if ok { avviaTick(t) } else { isPlaying = false }
        }
    }

    private func avviaTick(_ t: UUID) {
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                guard let p = await MotoreAudio.shared.posizione(token: t), let self, self.token == t, !Task.isCancelled else { return }
                self.currentTime = p.tempo
                if !p.inRiproduzione { self.isPlaying = false; return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func pause() {
        isPlaying = false
        tick?.cancel()
        guard let t = token else { return }
        Task { await MotoreAudio.shared.pausa(token: t) }
    }

    func seek(to t: TimeInterval) {
        let v = max(0, min(duration, t))
        currentTime = v
        guard let token else { return }
        Task { await MotoreAudio.shared.vai(token: token, a: v) }
    }

    func skip(_ delta: TimeInterval) { seek(to: currentTime + delta) }

    func setRate(_ r: Float) {
        rate = r
        guard let token else { return }
        Task { await MotoreAudio.shared.velocità(token: token, r) }
    }

    func stop() {
        tick?.cancel()
        isPlaying = false
        if let t = token { Task { await MotoreAudio.shared.chiudi(token: t) } }
        token = nil
        url = nil
    }
}
