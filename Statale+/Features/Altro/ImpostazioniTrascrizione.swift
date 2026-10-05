import Network
import SwiftUI

/// Scelta del motore di trascrizione: Apple (predefinito), Whisper (download aggiuntivo), Remoto Pro (futuro).
struct ImpostazioniTrascrizioneView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("motoreTrascrizione") private var scelto = MotoreTrascrizione.apple.rawValue
    @State private var confermaDownload = false
    @State private var confermaElimina = false

    private var motore: MotoreTrascrizione { MotoreTrascrizione(rawValue: scelto) ?? .apple }

    var body: some View {
        List {
            Section {
                ForEach(MotoreTrascrizione.allCases, id: \.self) { m in
                    Button { seleziona(m) } label: { RigaMotore(motore: m, selezionato: m == motore, nota: nota(m)) }
                        .tint(.primary)
                        .disabled(!selezionabile(m))
                }
            } footer: {
                Text("Il motore scelto vale per le prossime trascrizioni. Le trascrizioni già fatte non cambiano: puoi rifarle dal menu della trascrizione.")
            }

            if app.whisper.stato != .assente || app.whisper.errore != nil {
                Section("Modello Whisper") {
                    switch app.whisper.stato {
                    case .download(let p):
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: p) {
                                Text("Download di Whisper Large v3 Turbo").font(.callout)
                            } currentValueLabel: {
                                Text("\(p.formatted(.percent.precision(.fractionLength(0)))) di \(WhisperLocale.dimensioneMB) MB")
                                    .font(.caption.monospacedDigit())
                            }
                            Text(NotaBackground.testo).font(.caption).foregroundStyle(.secondary)
                            Button("Annulla download", role: .destructive) { app.whisper.annulla() }
                                .font(.callout).buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    case .installato:
                        LabeledContent("Spazio occupato", value: ByteCountFormatter.string(fromByteCount: WhisperLocale.spazioOccupato, countStyle: .file))
                        Button("Elimina il modello", role: .destructive) { confermaElimina = true }
                    case .assente:
                        EmptyView()
                    }
                    if let e = app.whisper.errore {
                        Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Trascrizione")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $confermaDownload) {
            ConfermaDownloadWhisper { app.whisper.scarica() }
                .presentationDetents([.large])
        }
        .confirmationDialog("Eliminare il modello Whisper?", isPresented: $confermaElimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                app.whisper.elimina()
                scelto = MotoreTrascrizione.apple.rawValue
            }
        } message: {
            Text("Libera circa \(WhisperLocale.dimensioneMB) MB. Le trascrizioni useranno di nuovo il motore di Apple; potrai riscaricare Whisper quando vuoi.")
        }
    }

    private func selezionabile(_ m: MotoreTrascrizione) -> Bool {
        switch m {
        case .apple: true
        case .whisper: WhisperLocale.supportato
        case .remoto: false
        }
    }

    private func nota(_ m: MotoreTrascrizione) -> String? {
        switch m {
        case .apple: return nil
        case .whisper:
            if !WhisperLocale.supportato { return "Richiede un iPhone con chip A15 o successivo (iPhone 13 e successivi)." }
            switch app.whisper.stato {
            case .installato: return "Scaricato e pronto."
            case .download: return "Download in corso…"
            case .assente: return "Toccalo per scaricarlo (\(WhisperLocale.dimensioneMB) MB)."
            }
        case .remoto: return "Non ancora disponibile."
        }
    }

    private func seleziona(_ m: MotoreTrascrizione) {
        switch m {
        case .apple:
            scelto = m.rawValue
        case .whisper:
            if app.whisper.stato == .installato { scelto = m.rawValue } else if app.whisper.stato == .assente { confermaDownload = true }
        case .remoto:
            break
        }
    }
}

private struct RigaMotore: View {
    let motore: MotoreTrascrizione
    let selezionato: Bool
    let nota: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: simbolo).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(motore.nome).font(.headline)
                    if motore == .remoto {
                        Text("PRO").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.orange, in: Capsule())
                    }
                }
                Text(motore.caratteristiche.joined(separator: " · ")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(motore.descrizione).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let nota { Text(nota).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if selezionato { Image(systemName: "checkmark").font(.headline).foregroundStyle(Color.accentColor) }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var simbolo: String {
        switch motore {
        case .apple: "apple.logo"
        case .whisper: "waveform.badge.mic"
        case .remoto: "cloud"
        }
    }
}

/// Avviso prima del download di Whisper: dimensione, spazio libero, rete, primo piano, batteria.
private struct ConfermaDownloadWhisper: View {
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
                        Text("Scaricare Whisper?").font(.title2.bold())
                        Text("Whisper Large v3 Turbo trascrive le lezioni con più precisione, tutto sul dispositivo. Serve un download aggiuntivo, da fare una sola volta.")
                            .font(.callout)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }
                Section {
                    voce("externaldrive", "Download aggiuntivo di \(WhisperLocale.dimensioneMB) MB",
                         spazioLibero.map { "Spazio libero sul dispositivo: \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))." }
                            ?? "Il modello resta sul dispositivo finché non lo elimini.")
                    voce("wifi", "Meglio con il Wi-Fi",
                         rete.cellulare
                            ? "Sei connesso con la rete cellulare: potrebbero essere applicati costi secondo la tua tariffa."
                            : "Con la rete cellulare potrebbero essere applicati costi secondo la tua tariffa.")
                    voce("iphone", "Tieni l'app in primo piano", NotaBackground.testo)
                    voce("battery.50percent", "Più pesante del motore di Apple",
                         "La trascrizione richiede più tempo e consuma più batteria, soprattutto per le registrazioni lunghe. La prima trascrizione prepara il modello e può richiedere qualche minuto in più.")
                    voce("lock.shield", "Privato", "Audio e testo non lasciano il dispositivo: il modello si scarica da Hugging Face (Argmax) e funziona offline.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        conferma()
                        dismiss()
                    } label: {
                        Text("Scarica \(WhisperLocale.dimensioneMB) MB").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Non ora") { dismiss() }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Whisper")
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

/// Nota sui lavori lunghi: da iOS 26 continuano uscendo dall'app, ma in primo piano sono più rapidi.
nonisolated enum NotaBackground {
    static var testo: String {
        if #available(iOS 26.0, *) {
            "Puoi uscire dall'app: iOS continua il lavoro e ne mostra l'avanzamento. In primo piano però è più veloce e più sicuro."
        } else {
            "Tieni l'app aperta finché non finisce: uscendo, il lavoro si ferma dopo pochi secondi e riprende quando torni."
        }
    }
}
