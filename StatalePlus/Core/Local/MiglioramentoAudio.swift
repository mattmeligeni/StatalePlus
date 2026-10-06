import Accelerate
import AVFoundation

/// Miglioramento offline delle registrazioni delle lezioni (voce lontana, volume basso, fruscio e ronzio di fondo),
/// per l'ascolto e per la trascrizione. Tutto in streaming a blocchi (nessun file temporaneo: 3 ore di PCM
/// sarebbero quasi 2 GB), fuori dal main thread e senza sessione audio. La catena:
/// 1. **riduzione del rumore** spettrale (STFT 1024 punti, stima continua del rumore di fondo per frequenza con le
///    statistiche dei minimi, guadagno di tipo Wiener con attenuazione massima di 12 dB e levigatura nel tempo
///    per evitare il "rumore musicale");
/// 2. **equalizzazione** per la voce: passa-alto 90 Hz, −2 dB a 250 Hz (rimbombo), +4 dB a 3 kHz (intelligibilità),
///    passa-basso 7,5 kHz (sibilo);
/// 3. **dinamica**: espansore sotto una soglia ricavata dalla registrazione (abbassa il fondo nelle pause) e
///    compressore sopra (avvicina voce vicina e lontana);
/// 4. **normalizzazione** a −16 LUFS circa (livello tipico del parlato; `loudnorm` di ffmpeg usa −24) con limitatore
///    di picco a −3 dBFS (margine per la codifica), poi AAC 64 kbps mono.
/// Tre letture del file: statistiche dopo pulizia ed equalizzazione, loudness dopo la dinamica, scrittura.
nonisolated enum MiglioramentoAudio {
    static let loudnessObiettivo: Float = -16

    enum Errore: LocalizedError {
        case vuoto, formato
        var errorDescription: String? {
            switch self {
            case .vuoto: "La registrazione non contiene audio da migliorare."
            case .formato: "Formato audio non supportato."
            }
        }
    }

    /// Elabora `input` e scrive il risultato in `output` (m4a). `progresso` riceve 0…1.
    @concurrent
    static func migliora(_ input: URL, in output: URL, progresso: @escaping @Sendable (Double) -> Void) async throws {
        let sr = try AVAudioFile(forReading: input).processingFormat.sampleRate
        guard sr > 0 else { throw Errore.formato }

        // 1. Livelli dopo riduzione del rumore ed equalizzazione.
        var livelli = Istogramma()
        let c1 = Catena(sampleRate: sr, dinamica: nil, guadagno: 1, limitatore: false)
        try await elabora(input, catena: c1, scrivi: nil, progresso: { progresso($0 * 0.3) }) { _ in } inviluppo: { livelli.aggiungi($0) }
        guard let fondo = livelli.percentile(0.10), let voce = livelli.percentile(0.95), voce > -80 else { throw Errore.vuoto }
        let dinamica = Dinamica.Parametri(fondo: fondo, voce: voce)

        // 2. Loudness dopo la dinamica.
        var misuratore = MisuratoreLoudness(sampleRate: sr)
        let c2 = Catena(sampleRate: sr, dinamica: dinamica, guadagno: 1, limitatore: false)
        try await elabora(input, catena: c2, scrivi: nil, progresso: { progresso(0.3 + $0 * 0.3) }) { misuratore.aggiungi($0) } inviluppo: { _ in }
        let loudness = misuratore.integrata
        guard loudness > -80 else { throw Errore.vuoto }
        let guadagno = pow(10, min(36, max(-20, loudnessObiettivo - loudness)) / 20)

        // 3. Scrittura con normalizzazione e limitatore.
        try? FileManager.default.removeItem(at: output)
        guard let formato = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: 1, interleaved: false) else { throw Errore.formato }
        let aac: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(forWriting: output, settings: aac, commonFormat: .pcmFormatFloat32, interleaved: false)
        let c3 = Catena(sampleRate: sr, dinamica: dinamica, guadagno: Float(guadagno), limitatore: true)
        try await elabora(input, catena: c3, scrivi: { campioni in
            guard !campioni.isEmpty, let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: AVAudioFrameCount(campioni.count)) else { return }
            b.frameLength = AVAudioFrameCount(campioni.count)
            campioni.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: campioni.count) }
            try file.write(from: b)
        }, progresso: { progresso(0.6 + $0 * 0.4) }) { _ in } inviluppo: { _ in }
        progresso(1)
    }

    /// Legge il file a blocchi, lo fa passare nella catena e consegna l'uscita (stessa lunghezza dell'ingresso).
    private static func elabora(_ url: URL, catena: Catena, scrivi: (([Float]) throws -> Void)?,
                                progresso: (Double) -> Void, uscita: ([Float]) -> Void,
                                inviluppo: (Float) -> Void) async throws {
        let file = try AVAudioFile(forReading: url)
        let capacità: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacità) else { throw Errore.formato }
        let totale = file.length
        var daScartare = catena.latenza
        var scritti: Int64 = 0

        func consegna(_ blocco: [Float]) throws {
            var b = blocco[...]
            if daScartare > 0 {
                let n = min(daScartare, b.count)
                b = b.dropFirst(n)
                daScartare -= n
            }
            let restanti = Int(totale - scritti)
            if b.count > restanti { b = b.prefix(restanti) }
            guard !b.isEmpty else { return }
            let a = Array(b)
            scritti += Int64(a.count)
            uscita(a)
            try scrivi?(a)
        }

        var ultimo = -1.0
        while file.framePosition < totale {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: capacità)
            let n = Int(buffer.frameLength)
            guard n > 0, let dati = buffer.floatChannelData?[0] else { break }
            try consegna(catena.processa(Array(UnsafeBufferPointer(start: dati, count: n)), inviluppo: inviluppo))
            let p = Double(file.framePosition) / Double(totale)
            if p - ultimo >= 0.01 { ultimo = p; progresso(p) }
            await Task.yield()
        }
        // Coda: zeri per svuotare i ritardi interni.
        try consegna(catena.processa([Float](repeating: 0, count: catena.latenza + RiduzioneRumore.n + 2048), inviluppo: { _ in }))
    }
}

// MARK: - Catena

private nonisolated final class Catena {
    let latenza: Int
    private let riduzione: RiduzioneRumore
    private var eq: vDSP.Biquad<Float>
    private let dinamica: Dinamica?
    private let guadagno: Float
    private let limitatore: Limitatore?

    init(sampleRate sr: Double, dinamica p: Dinamica.Parametri?, guadagno: Float, limitatore: Bool) {
        riduzione = RiduzioneRumore(sampleRate: sr)
        eq = Catena.equalizzatore(sr)
        dinamica = Dinamica(sampleRate: sr, parametri: p)
        self.guadagno = guadagno
        self.limitatore = limitatore ? Limitatore(sampleRate: sr) : nil
        latenza = RiduzioneRumore.latenza + (limitatore ? Limitatore.latenza : 0)
    }

    func processa(_ x: [Float], inviluppo: (Float) -> Void) -> [Float] {
        var y = riduzione.processa(x)
        guard !y.isEmpty else { return y }
        y = eq.apply(input: y)
        dinamica?.processa(&y, inviluppo: inviluppo)
        if guadagno != 1 { vDSP.multiply(guadagno, y, result: &y) }
        if let limitatore { y = limitatore.processa(y) }
        return y
    }

    /// Biquad RBJ (coefficienti normalizzati [b0, b1, b2, a1, a2]).
    private static func equalizzatore(_ sr: Double) -> vDSP.Biquad<Float> {
        func sezione(_ tipo: String, _ f: Double, _ q: Double, _ dB: Double = 0) -> [Double] {
            let w = 2 * Double.pi * f / sr, cw = cos(w), sw = sin(w), alpha = sw / (2 * q)
            let a = pow(10, dB / 40)
            var b0, b1, b2, a0, a1, a2: Double
            switch tipo {
            case "hp":
                b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
            case "lp":
                b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
                a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
            default: // peaking
                b0 = 1 + alpha * a; b1 = -2 * cw; b2 = 1 - alpha * a
                a0 = 1 + alpha / a; a1 = -2 * cw; a2 = 1 - alpha / a
            }
            return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
        }
        let coeff = sezione("hp", 90, 0.707) + sezione("pk", 250, 0.9, -2) + sezione("pk", 3000, 0.8, 4) + sezione("lp", 7500, 0.707)
        return vDSP.Biquad(coefficients: coeff, channelCount: 1, sectionCount: 4, ofType: Float.self)!
    }
}

// MARK: - Riduzione del rumore

/// Sottrazione spettrale (guadagno di Wiener) su STFT con finestre radice-di-Hann al 50 %: ricostruzione perfetta
/// quando il guadagno è 1. Il rumore per frequenza è il minimo della potenza levigata sugli ultimi ~3 s
/// (statistiche dei minimi): segue da solo condizionatori, ventole e fruscio che cambiano durante la lezione.
private nonisolated final class RiduzioneRumore {
    static let n = 1024
    static let hop = n / 2
    /// Il campione d'uscita j corrisponde all'ingresso j (nessuno sfasamento da scartare); a fine file servono
    /// `n` campioni di zeri per svuotare l'ultimo frame.
    static let latenza = 0
    private static let bins = n / 2 + 1
    private static let sottofinestre = 8, framePerSottofinestra = 32      // 8 × 32 × 11,6 ms ≈ 3 s
    private static let attenuazioneMassima: Float = 0.25                // −12 dB
    private static let sovrasottrazione: Float = 1.5
    private static let correzioneMinimo: Float = 2.5

    private let finestra: [Float]
    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let idft: vDSP.DiscreteFourierTransform<Float>
    private var ingresso: [Float] = []
    private var accumulo = [Float](repeating: 0, count: n)
    private var levigata = [Float](repeating: 0, count: bins)
    private var minimoCorrente = [Float](repeating: .greatestFiniteMagnitude, count: bins)
    private var minimi: [[Float]] = []
    private var contaFrame = 0
    private var guadagnoPrecedente = [Float](repeating: 1, count: bins)
    private var primoFrame = true
    private var scala: Float = 1

    init(sampleRate _: Double) {
        let n = Self.n
        finestra = (0..<n).map { sqrt(0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(n))) }
        dft = try! vDSP.DiscreteFourierTransform(count: n, direction: .forward, transformType: .complexReal, ofType: Float.self)
        idft = try! vDSP.DiscreteFourierTransform(count: n, direction: .inverse, transformType: .complexReal, ofType: Float.self)
        scala = 1 / Float(2 * n)                                          // andata e ritorno di zrop = 2N
        ingresso.reserveCapacity(n * 4)
    }

    func processa(_ x: [Float]) -> [Float] {
        ingresso.append(contentsOf: x)
        var uscita: [Float] = []
        uscita.reserveCapacity(x.count + Self.hop)
        var inizio = 0
        while ingresso.count - inizio >= Self.n {
            uscita.append(contentsOf: frame(Array(ingresso[inizio..<(inizio + Self.n)])))
            inizio += Self.hop
        }
        if inizio > 0 { ingresso.removeFirst(inizio) }
        return uscita
    }

    private func frame(_ campioni: [Float]) -> [Float] {
        let n = Self.n, meta = n / 2
        var w = [Float](repeating: 0, count: n)
        vDSP.multiply(campioni, finestra, result: &w)
        // complexReal: parte reale = campioni pari, immaginaria = dispari.
        var pari = [Float](repeating: 0, count: meta), dispari = [Float](repeating: 0, count: meta)
        for i in 0..<meta { pari[i] = w[2 * i]; dispari[i] = w[2 * i + 1] }
        var re = [Float](repeating: 0, count: meta), im = [Float](repeating: 0, count: meta)
        dft.transform(inputReal: pari, inputImaginary: dispari, outputReal: &re, outputImaginary: &im)

        // Potenza per bin: 0 = DC (re[0]), meta = Nyquist (im[0]).
        var potenza = [Float](repeating: 0, count: Self.bins)
        potenza[0] = re[0] * re[0]
        potenza[meta] = im[0] * im[0]
        for k in 1..<meta { potenza[k] = re[k] * re[k] + im[k] * im[k] }

        aggiornaRumore(potenza)
        var rumore = minimoCorrente
        for m in minimi { vDSP.minimum(rumore, m, result: &rumore) }
        vDSP.multiply(Self.correzioneMinimo, rumore, result: &rumore)

        var g = [Float](repeating: 1, count: Self.bins)
        for k in 0..<Self.bins {
            let p = max(potenza[k], 1e-20)
            var gk = max(Self.attenuazioneMassima, 1 - Self.sovrasottrazione * rumore[k] / p)
            // Apertura rapida, chiusura lenta: niente "rumore musicale".
            if gk < guadagnoPrecedente[k] { gk = 0.6 * guadagnoPrecedente[k] + 0.4 * gk }
            g[k] = gk
        }
        guadagnoPrecedente = g

        re[0] *= g[0]
        im[0] *= g[meta]
        for k in 1..<meta { re[k] *= g[k]; im[k] *= g[k] }
        var oPari = [Float](repeating: 0, count: meta), oDispari = [Float](repeating: 0, count: meta)
        idft.transform(inputReal: re, inputImaginary: im, outputReal: &oPari, outputImaginary: &oDispari)
        var y = [Float](repeating: 0, count: n)
        for i in 0..<meta { y[2 * i] = oPari[i]; y[2 * i + 1] = oDispari[i] }
        vDSP.multiply(scala, y, result: &y)
        vDSP.multiply(y, finestra, result: &y)
        vDSP.add(accumulo, y, result: &accumulo)
        let pronta = Array(accumulo[0..<Self.hop])
        accumulo.removeFirst(Self.hop)
        accumulo.append(contentsOf: [Float](repeating: 0, count: Self.hop))
        return pronta
    }

    private func aggiornaRumore(_ potenza: [Float]) {
        if primoFrame {
            levigata = potenza
            primoFrame = false
        } else {
            vDSP.add(vDSP.multiply(0.85, levigata), vDSP.multiply(0.15, potenza), result: &levigata)
        }
        vDSP.minimum(minimoCorrente, levigata, result: &minimoCorrente)
        contaFrame += 1
        if contaFrame == Self.framePerSottofinestra {
            minimi.append(minimoCorrente)
            if minimi.count > Self.sottofinestre { minimi.removeFirst() }
            minimoCorrente = levigata
            contaFrame = 0
        }
    }
}

// MARK: - Dinamica

/// Espansore verso il basso + compressore, con inviluppo in dB calcolato su blocchi da 64 campioni (~1,5 ms)
/// e guadagno interpolato linearmente dentro il blocco.
private nonisolated final class Dinamica {
    struct Parametri {
        let sogliaEspansore: Float
        let sogliaCompressore: Float
        /// `fondo`: livello tipico delle pause (10° percentile dell'inviluppo); `voce`: parlato (95° percentile).
        init(fondo: Float, voce: Float) {
            let distanza = max(voce - fondo, 6)
            sogliaEspansore = fondo + distanza * 0.35
            sogliaCompressore = voce - 10
        }
    }

    static let blocco = 64
    private let p: Parametri?
    private let attacco: Float, rilascio: Float
    private var inviluppo: Float = -100
    private var guadagnoPrecedente: Float = 1

    init?(sampleRate sr: Double, parametri: Parametri?) {
        p = parametri
        let durata = Float(Self.blocco) / Float(sr)
        attacco = exp(-durata / 0.005)
        rilascio = exp(-durata / 0.15)
    }

    func processa(_ y: inout [Float], inviluppo osserva: (Float) -> Void) {
        var i = 0
        while i < y.count {
            let fine = min(i + Self.blocco, y.count)
            var ms: Float = 0
            y[i..<fine].withUnsafeBufferPointer { vDSP_measqv($0.baseAddress!, 1, &ms, vDSP_Length($0.count)) }
            let livello = 10 * log10(max(ms, 1e-12))
            inviluppo = livello > inviluppo ? attacco * inviluppo + (1 - attacco) * livello
                                            : rilascio * inviluppo + (1 - rilascio) * livello
            osserva(inviluppo)
            if let p {
                var gDB: Float = 0
                if inviluppo < p.sogliaEspansore { gDB = max(-18, -(p.sogliaEspansore - inviluppo) * 1.5) }       // rapporto 1:2,5
                else if inviluppo > p.sogliaCompressore { gDB = -(inviluppo - p.sogliaCompressore) * (1 - 1 / 3) } // 3:1
                let g = pow(10, gDB / 20)
                let passo = (g - guadagnoPrecedente) / Float(fine - i)
                for j in i..<fine { y[j] *= guadagnoPrecedente + passo * Float(j - i + 1) }
                guadagnoPrecedente = g
            }
            i = fine
        }
    }
}

// MARK: - Limitatore

/// Limitatore di picco a −3 dBFS. Anticipo di due blocchi (2 × 64 campioni, ~3 ms): il guadagno scende con una
/// rampa lineare e arriva al valore necessario prima del picco, senza gradini (che la codifica AAC trasformerebbe
/// in picchi oltre 0 dB). Rilascio di 80 ms.
private nonisolated final class Limitatore {
    static let blocco = 64
    static let latenza = 2 * blocco
    private let soglia: Float = 0.707         // −3 dBFS: l'AAC sui transitori sfora fino a ~2,5 dB
    private let rilascio: Float
    private var blocchi: [[Float]] = [[Float](repeating: 0, count: blocco), [Float](repeating: 0, count: blocco)]
    private var guadagno: Float = 1
    private var coda: [Float] = []

    init(sampleRate sr: Double) { rilascio = 1 - exp(-Float(Self.blocco) / Float(sr) / 0.08) }

    func processa(_ x: [Float]) -> [Float] {
        coda.append(contentsOf: x)
        var uscita: [Float] = []
        uscita.reserveCapacity(coda.count)
        var inizio = 0
        while coda.count - inizio >= Self.blocco {
            blocchi.append(Array(coda[inizio..<(inizio + Self.blocco)]))
            inizio += Self.blocco
            // blocchi[0] esce ora; [1] e [2] sono l'anticipo. Il guadagno a fine rampa rispetta tutti e tre,
            // quello d'inizio rispettava già [0] (era nell'anticipo al giro precedente).
            let picco = blocchi.map { vDSP.maximumMagnitude($0) }.max() ?? 0
            let necessario = picco > soglia ? soglia / picco : 1
            let nuovo = necessario < guadagno ? necessario : min(necessario, guadagno + (1 - guadagno) * rilascio)
            var out = blocchi.removeFirst()
            let passo = (nuovo - guadagno) / Float(Self.blocco)
            for j in 0..<Self.blocco { out[j] *= guadagno + passo * Float(j + 1) }
            vDSP.clip(out, to: -soglia...soglia, result: &out)
            uscita.append(contentsOf: out)
            guadagno = nuovo
        }
        if inizio > 0 { coda.removeFirst(inizio) }
        return uscita
    }
}

// MARK: - Misure

/// Istogramma dei livelli dell'inviluppo (dB, passo 0,5) per percentili senza tenere in memoria tutti i valori.
private nonisolated struct Istogramma {
    private var conteggi = [Int](repeating: 0, count: 400)     // −160 … 40 dB
    private var totale = 0

    mutating func aggiungi(_ db: Float) {
        guard db.isFinite else { return }
        let i = min(399, max(0, Int((db + 160) * 2)))
        conteggi[i] += 1
        totale += 1
    }

    func percentile(_ q: Double) -> Float? {
        guard totale > 0 else { return nil }
        let obiettivo = Int(Double(totale) * q)
        var somma = 0
        for (i, c) in conteggi.enumerated() {
            somma += c
            if somma > obiettivo { return Float(i) / 2 - 160 }
        }
        return nil
    }
}

/// Loudness integrata con gating (blocchi da 400 ms, soglia assoluta −70 dB, relativa −10 dB).
nonisolated struct MisuratoreLoudness {
    private let dimensioneBlocco: Int
    private var somma: Double = 0
    private var conteggio = 0
    private var blocchi: [Float] = []       // energia media per blocco

    init(sampleRate: Double) { dimensioneBlocco = max(1, Int(sampleRate * 0.4)) }

    mutating func aggiungi(_ x: [Float]) {
        var i = 0
        while i < x.count {
            let n = min(dimensioneBlocco - conteggio, x.count - i)
            var sq: Float = 0
            x.withUnsafeBufferPointer { vDSP_svesq($0.baseAddress! + i, 1, &sq, vDSP_Length(n)) }
            somma += Double(sq)
            conteggio += n
            i += n
            if conteggio == dimensioneBlocco {
                blocchi.append(Float(somma / Double(conteggio)))
                somma = 0
                conteggio = 0
            }
        }
    }

    var integrata: Float {
        func db(_ e: Float) -> Float { 10 * log10(max(e, 1e-12)) }
        let assoluti = blocchi.filter { db($0) > -70 }
        guard !assoluti.isEmpty else { return -120 }
        let soglia = db(assoluti.reduce(0, +) / Float(assoluti.count)) - 10
        let relativi = assoluti.filter { db($0) > soglia }
        guard !relativi.isEmpty else { return -120 }
        return db(relativi.reduce(0, +) / Float(relativi.count))
    }
}
