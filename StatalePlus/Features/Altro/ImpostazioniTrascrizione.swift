import Network
import SwiftUI

/// Scelta del motore di trascrizione: Apple (nessun download), Parakeet (più accurato), Remoto Pro (futuro).
struct ImpostazioniTrascrizioneView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("motoreTrascrizione") private var scelto = MotoreTrascrizione.apple.rawValue
    @State private var confermaDownload = false

    private var motore: MotoreTrascrizione {
        let m = MotoreTrascrizione(rawValue: scelto) ?? .apple
        return m == .parakeet && app.parakeet.stato != .installato ? .apple : m
    }

    var body: some View {
        List {
            Section {
                ForEach(MotoreTrascrizione.allCases, id: \.self) { m in
                    Button { seleziona(m) } label: {
                        RigaMotore(nome: m.nome, simbolo: simbolo(m), caratteristiche: m.caratteristiche, descrizione: m.descrizione,
                                   selezionato: m == motore, nota: nota(m), avanzamento: avanzamento(m), pro: m == .remoto)
                    }
                    .tint(.primary)
                    .disabled(m == .remoto)
                }
            } footer: {
                Text("Le trascrizioni già fatte non cambiano: puoi rifarle dal menu della trascrizione.")
            }
            SezioneModello(gestore: app.parakeet)
        }
        .navigationTitle("Trascrizione")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { app.parakeet.ricontrolla() }
        .sheet(isPresented: $confermaDownload) {
            ConfermaDownloadParakeet(gestore: app.parakeet).presentationDetents([.large])
        }
    }

    private func simbolo(_ m: MotoreTrascrizione) -> String {
        switch m {
        case .apple: "apple.logo"
        case .parakeet: "waveform.badge.mic"
        case .remoto: "cloud"
        }
    }

    private func nota(_ m: MotoreTrascrizione) -> String? {
        switch m {
        case .apple: return nil
        case .remoto: return "Non ancora disponibile."
        case .parakeet:
            switch app.parakeet.stato {
            case .installato: return "Scaricato e pronto."
            case .download: return nil
            case .assente: return "Toccalo per scaricarlo (\(ParakeetLocale.dimensioneMB) MB)."
            }
        }
    }

    private func avanzamento(_ m: MotoreTrascrizione) -> Double? {
        if m == .parakeet, case .download(let p) = app.parakeet.stato { return p }
        return nil
    }

    private func seleziona(_ m: MotoreTrascrizione) {
        switch m {
        case .apple: scelto = m.rawValue
        case .parakeet:
            if app.parakeet.stato == .installato { scelto = m.rawValue } else if app.parakeet.stato == .assente { confermaDownload = true }
        case .remoto: break
        }
    }
}

/// Scelta del motore dei riassunti: Apple Intelligence online (predefinita, quando Apple la abilita per l'app), sul
/// telefono, oppure Qwen scaricabile (riassunti più completi, anche sugli iPhone senza Apple Intelligence). Se quella
/// online non è raggiungibile o il limite giornaliero è finito, si usa quella sul telefono.
struct ImpostazioniRiassuntiView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("motoreRiassunto") private var scelto = MotoreRiassunto.cloud.rawValue
    @State private var confermaDownload = false

    var body: some View {
        List {
            Section {
                if QwenLocale.supportato {
                    Button(action: selezionaQwen) {
                        RigaMotore(nome: "Qwen 3.5", simbolo: "text.book.closed",
                                   caratteristiche: ["Sul telefono", "Offline", "Più completo"],
                                   descrizione: "Appunti più completi e spiegati, con punti chiave e domande di ripasso. Lavora con l'app aperta: se esci si mette in pausa e riprende quando torni.",
                                   selezionato: effettivo == .qwen, nota: notaQwen, avanzamento: avanzamentoQwen, pro: false)
                    }
                    .tint(.primary)
                }
                Button { scelto = MotoreRiassunto.cloud.rawValue } label: {
                    RigaMotore(nome: "Apple Intelligence online", simbolo: "icloud",
                               caratteristiche: ["Online", "Più veloce"],
                               descrizione: "Il modello più grande di Apple: riassunti completi e ordinati. Il testo della lezione va ad Apple, che non lo conserva. Riassunti al giorno limitati.",
                               selezionato: effettivo == .cloud, nota: notaCloud, avanzamento: nil, pro: false)
                }
                .tint(.primary)
                .disabled(NuvolaApple.stato != .disponibile)
                Button { scelto = MotoreRiassunto.apple.rawValue } label: {
                    RigaMotore(nome: "Apple Intelligence", simbolo: "apple.intelligence",
                               caratteristiche: ["Sul telefono", "Offline", "Nessun download"],
                               descrizione: "Il testo resta sul telefono e il lavoro continua anche fuori dall'app. Riassunti più brevi.",
                               selezionato: effettivo == .apple, nota: notaApple, avanzamento: nil, pro: false)
                }
                .tint(.primary)
                .disabled(AppleIntelligence.stato != .disponibile)
            } footer: {
                Text("Il glossario del corso si crea sempre con Apple Intelligence. La trascrizione resta sempre sul telefono.")
            }
            if effettivo == .cloud, NuvolaApple.puòAumentareLimite {
                Section {
                    Button("Più riassunti al giorno con iCloud+") { NuvolaApple.mostraAumentoLimite() }
                }
            }
            SezioneModello(gestore: app.qwen)
        }
        .navigationTitle("Riassunti")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { app.qwen.ricontrolla() }
        .sheet(isPresented: $confermaDownload) {
            ConfermaDownloadQwen(gestore: app.qwen).presentationDetents([.large])
        }
    }

    /// Il motore che si userà davvero (dipende anche da cosa è disponibile ora).
    private var effettivo: MotoreRiassunto? {
        _ = scelto
        _ = app.qwen.stato
        return MotoreRiassunto.disponibile
    }

    private func selezionaQwen() {
        switch app.qwen.stato {
        case .installato: scelto = MotoreRiassunto.qwen.rawValue
        case .assente: confermaDownload = true
        case .download: break
        }
    }

    private var notaQwen: String? {
        switch app.qwen.stato {
        case .installato: "Scaricato e pronto."
        case .download: nil
        case .assente: "Toccalo per scaricarlo (\(QwenLocale.dimensioneMB) MB)."
        }
    }

    private var avanzamentoQwen: Double? {
        if case .download(let p) = app.qwen.stato { return p }
        return nil
    }

    private var notaCloud: String? {
        switch NuvolaApple.stato {
        case .nonDisponibile(let motivo): motivo
        case .nonAutorizzata: "Presto disponibile."
        case .disponibile: NuvolaApple.notaLimite ?? (scelto == MotoreRiassunto.cloud.rawValue
            ? "Senza connessione o oltre il limite si usa quella sul telefono." : nil)
        }
    }

    private var notaApple: String? {
        switch AppleIntelligence.stato {
        case .disponibile: nil
        case .nonAttiva: "Attiva Apple Intelligence in Impostazioni › Apple Intelligence e Siri."
        case .inPreparazione: "Apple Intelligence sta scaricando il modello."
        case .nonSupportata: "Non disponibile su questo iPhone o con questa versione di iOS."
        }
    }
}

/// Conferma del download di Qwen, uguale ovunque (impostazioni, presentazione, avvisi sotto i riassunti).
struct ConfermaDownloadQwen: View {
    let gestore: GestoreModello

    var body: some View {
        ConfermaDownloadModello(
            modello: gestore.modello,
            titolo: "Scaricare il modello per i riassunti?",
            testo: "Appunti più completi e spiegati, scritti sul telefono. Il download si fa una volta sola.",
            consumi: "Un'ora di lezione in qualche minuto, con l'app aperta."
        ) { gestore.scarica() }
    }
}

/// Conferma del download di Parakeet, uguale ovunque (impostazioni, presentazione, avvisi sotto le trascrizioni).
struct ConfermaDownloadParakeet: View {
    let gestore: GestoreModello

    var body: some View {
        ConfermaDownloadModello(
            modello: gestore.modello,
            titolo: "Scaricare il modello più preciso?",
            testo: "Trascrizioni più precise, soprattutto con termini tecnici e nomi, sul telefono. Il download si fa una volta sola.",
            consumi: "Due ore di lezione in pochi minuti, con poca batteria."
        ) { gestore.scarica() }
    }
}

/// Stato del modello scaricato: avanzamento con annulla, spazio occupato ed eliminazione, errori.
private struct SezioneModello: View {
    let gestore: GestoreModello
    @State private var confermaElimina = false

    var body: some View {
        if gestore.stato != .assente || gestore.errore != nil {
            Section("Modello scaricato") {
                switch gestore.stato {
                case .download(let p):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Download di \(gestore.modello.nome)").font(.callout)
                        BarraDownload(avanzamento: p, totaleMB: gestore.modello.dimensioneMB)
                        Text(NotaBackground.testo).font(.caption).foregroundStyle(.secondary)
                        Button("Annulla download", role: .destructive) { gestore.annulla() }
                            .font(.callout).buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                case .installato:
                    LabeledContent("Spazio occupato", value: ByteCountFormatter.string(fromByteCount: gestore.spazioOccupato, countStyle: .file))
                    Button("Elimina il modello", role: .destructive) { confermaElimina = true }
                case .assente:
                    EmptyView()
                }
                if let e = gestore.errore {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
            }
            .confirmationDialog("Eliminare il modello \(gestore.modello.nome)?", isPresented: $confermaElimina, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) { gestore.elimina() }
            } message: {
                Text("Libera circa \(gestore.modello.dimensioneMB) MB. Si userà di nuovo il modello di Apple; potrai riscaricarlo quando vuoi.")
            }
        }
    }
}

private struct RigaMotore: View {
    let nome: String
    let simbolo: String
    let caratteristiche: [String]
    let descrizione: String
    let selezionato: Bool
    let nota: String?
    let avanzamento: Double?
    let pro: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: simbolo).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(nome).font(.headline)
                    if pro {
                        Text("PRO").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.orange, in: Capsule())
                    }
                }
                Text(caratteristiche.joined(separator: " · ")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(descrizione).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let nota { Text(nota).font(.caption).foregroundStyle(.secondary) }
                if let avanzamento { BarraDownload(avanzamento: avanzamento).padding(.top, 2) }
            }
            Spacer(minLength: 0)
            if selezionato { Image(systemName: "checkmark").font(.headline).foregroundStyle(Color.accentColor) }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Barra del download del modello con percentuale e, se noto il totale, MB scaricati.
struct BarraDownload: View {
    let avanzamento: Double
    var totaleMB: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: avanzamento)
                .tint(.accentColor)
                .animation(.easeOut(duration: 0.4), value: avanzamento)
            HStack {
                Text(avanzamento.formatted(.percent.precision(.fractionLength(0))))
                Spacer()
                if let totaleMB {
                    Text("\(Int((avanzamento * Double(totaleMB)).rounded())) di \(totaleMB) MB")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

/// Avviso prima del download di un modello: dimensione, spazio libero, rete, primo piano, consumi, privacy.
struct ConfermaDownloadModello: View {
    let modello: ModelloLocale
    let titolo: String
    let testo: String
    let consumi: String
    let conferma: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rete = StatoRete()

    private var spazioLibero: Int64? {
        (try? URL.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                        Text(titolo).font(.title2.bold())
                        Text(testo).font(.callout)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }
                Section {
                    voce("externaldrive", "Download aggiuntivo di \(modello.dimensioneMB) MB",
                         spazioLibero.map { "Spazio libero sul dispositivo: \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))." }
                            ?? "Il modello resta sul dispositivo finché non lo elimini.")
                    voce("wifi", "Meglio con il Wi-Fi",
                         rete.cellulare
                            ? "Sei connesso con la rete cellulare: potrebbero essere applicati costi secondo la tua tariffa."
                            : "Con la rete cellulare potrebbero essere applicati costi secondo la tua tariffa.")
                    voce("iphone", "Meglio con l'app aperta", NotaBackground.testo)
                    voce("battery.50percent", "Consumi", consumi)
                    voce("lock.shield", "Privato", "Dopo il download funziona offline: audio e testi restano sul telefono.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        conferma()
                        dismiss()
                    } label: {
                        Text("Scarica \(modello.dimensioneMB) MB").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Non ora") { dismiss() }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle(modello.nome)
            .navigationBarTitleDisplayMode(.inline)
            .task { await rete.aggiorna() }
        }
    }

    private func voce(_ simbolo: String, _ titolo: String, _ testo: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(titolo).font(.subheadline.weight(.semibold))
                Text(testo).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: simbolo).foregroundStyle(Color.accentColor)
        }
    }
}

/// Connessione attuale (per l'avviso sui costi della rete cellulare).
@Observable
private final class StatoRete {
    private(set) var cellulare = false

    func aggiorna() async {
        let monitor = NWPathMonitor()
        let percorso = await withCheckedContinuation { (c: CheckedContinuation<NWPath, Never>) in
            let fatto = UnaVoltaRete()
            monitor.pathUpdateHandler = { p in fatto.esegui { c.resume(returning: p) } }
            monitor.start(queue: DispatchQueue(label: "rete"))
        }
        monitor.cancel()
        cellulare = percorso.usesInterfaceType(.cellular) && !percorso.usesInterfaceType(.wifi)
    }
}

private nonisolated final class UnaVoltaRete: @unchecked Sendable {
    private let lock = NSLock()
    private var fatto = false
    func esegui(_ blocco: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !fatto else { return }
        fatto = true
        blocco()
    }
}

/// Nota sui lavori lunghi: continuano uscendo dall'app, ma in primo piano sono più rapidi.
nonisolated enum NotaBackground {
    /// Da iOS 27 il Neural Engine in background (Parakeet) richiede l'entitlement "Background Inference": la chiave
    /// `StataleNeuralEngineInBackground` di Info.plist va messa a `YES` insieme all'entitlement.
    static var neuralEngineInBackground: Bool {
        if #available(iOS 27.0, *) {
            return Bundle.main.object(forInfoDictionaryKey: "StataleNeuralEngineInBackground") as? Bool ?? false
        }
        return true
    }

    static let testo = "Puoi uscire dall'app: il lavoro continua. Con l'app aperta finisce prima."
}
