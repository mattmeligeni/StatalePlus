import SwiftUI

/// Registrazioni vocali delle lezioni, collegate agli insegnamenti attivati nell'orario.
/// Audio AAC mono 64 kbps (~29 MB/ora) in Application Support/Registrazioni, indice JSON accanto.
/// La registrazione continua a schermo bloccato (audio in background).
struct RegistrazioniView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""

    /// Insegnamenti con almeno una registrazione, dal più recente.
    private var gruppi: [GruppoRegistrazioni] {
        Dictionary(grouping: app.recordings.items) { $0.insegnamento ?? GruppoRegistrazioni.senza }
            .map { GruppoRegistrazioni(nome: $0.key, items: $0.value.sorted { $0.creata > $1.creata }) }
            .sorted { ($0.items.first?.creata ?? .distantPast) > ($1.items.first?.creata ?? .distantPast) }
    }

    private var risultati: [Registrazione] {
        let q = query.trimmed
        return app.recordings.items.filter {
            $0.titolo.localizedCaseInsensitiveContains(q) || ($0.insegnamento ?? "").localizedCaseInsensitiveContains(q)
                || $0.note.localizedCaseInsensitiveContains(q)
        }
        .sorted { $0.creata > $1.creata }
    }

    private var daVerificare: [Registrazione] { app.recordings.items.filter(\.richiedeVerifica) }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            List {
                Section { RecorderCard() }
                if app.recordings.items.isEmpty {
                    ContentUnavailableView("Nessuna registrazione", systemImage: "waveform",
                                           description: Text("Scegli un insegnamento e avvia la registrazione durante la lezione."))
                        .listRowBackground(Color.clear)
                } else if query.trimmed.isEmpty {
                    Section("Insegnamenti") {
                        ForEach(gruppi) { g in
                            NavigationLink { RegistrazioniInsegnamentoView(nome: g.nome) } label: { GruppoRow(gruppo: g) }
                        }
                    }
                } else {
                    Section("Risultati") {
                        if risultati.isEmpty { Text("Nessuna registrazione trovata").foregroundStyle(.secondary) }
                        ForEach(risultati) { r in
                            NavigationLink { RegistrazioneDetailView(id: r.id) } label: { RegistrazioneRow(r: r, mostraInsegnamento: true) }
                        }
                    }
                }
                if query.trimmed.isEmpty && !daVerificare.isEmpty {
                    Section {
                        NavigationLink { RegistrazioniDaVerificareView() } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Da verificare").font(.subheadline.weight(.semibold))
                                    Text(daVerificare.count == 1 ? "1 registrazione recuperata dai file" : "\(daVerificare.count) registrazioni recuperate dai file")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                        }
                    } footer: {
                        Text("Data, ora e insegnamento sono stati ricavati dal file audio e dall'orario: controllali e conferma.")
                    }
                }
                if let errore = app.recordings.ultimoErrore {
                    Section {
                        Label(errore, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Registrazioni")
            .navigationDestination(isPresented: $app.mostraRecuperate) { RegistrazioniDaVerificareView() }
            .searchable(text: $query, prompt: "Titolo, insegnamento o note")
            .task { if app.lezioniUtente.updatedAt == nil { await app.loadLezioniUtente() } }
        }
    }
}

private struct GruppoRegistrazioni: Identifiable {
    static let senza = "Senza insegnamento"
    var id: String { nome }
    let nome: String
    let items: [Registrazione]
}

private struct GruppoRow: View {
    let gruppo: GruppoRegistrazioni
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: gruppo.nome == GruppoRegistrazioni.senza ? "waveform" : "book.closed.fill")
                .font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(gruppo.nome).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(gruppo.items.count == 1 ? "1 registrazione" : "\(gruppo.items.count) registrazioni")
                    Text("· \(durata(gruppo.items.reduce(0) { $0 + $1.durata }))")
                    if let ultima = gruppo.items.first?.creata {
                        Text("· \(ultima.italiano(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

/// Elenco delle registrazioni di un insegnamento.
private struct RegistrazioniInsegnamentoView: View {
    let nome: String
    @Environment(AppModel.self) private var app
    @State private var daEliminare: Registrazione?

    private var items: [Registrazione] {
        app.recordings.items.filter { ($0.insegnamento ?? GruppoRegistrazioni.senza) == nome }.sorted { $0.creata > $1.creata }
    }

    var body: some View {
        List {
            if items.isEmpty { Text("Nessuna registrazione").foregroundStyle(.secondary) }
            ForEach(items) { r in
                NavigationLink { RegistrazioneDetailView(id: r.id) } label: { RegistrazioneRow(r: r) }
                    // Niente `role: .destructive`: toglierebbe la riga dalla lista prima della conferma.
                    .swipeActions { Button("Elimina") { daEliminare = r }.tint(.red) }
            }
        }
        .navigationTitle(nome)
        .navigationBarTitleDisplayMode(.inline)
        .confermaEliminazione($daEliminare) { app.eliminaRegistrazione($0) }
    }
}

/// Registrazioni recuperate dai file, da controllare.
private struct RegistrazioniDaVerificareView: View {
    @Environment(AppModel.self) private var app

    private var items: [Registrazione] { app.recordings.items.filter(\.richiedeVerifica).sorted { $0.creata > $1.creata } }

    var body: some View {
        List {
            Section {
                if items.isEmpty { Text("Tutte le registrazioni sono state verificate").foregroundStyle(.secondary) }
                ForEach(items) { r in
                    NavigationLink { RegistrazioneDetailView(id: r.id) } label: { RegistrazioneRow(r: r, mostraInsegnamento: true) }
                }
            } footer: {
                Text("Queste registrazioni erano sul dispositivo ma non nell'elenco (salvate da una versione precedente dell'app o interrotte dalla chiusura dell'app). Sono state ripristinate in automatico: apri ognuna per ascoltarla e confermare data, ora e insegnamento, oppure eliminala.")
            }
            if !items.isEmpty {
                Section {
                    Button("Conferma tutte") { items.forEach { app.recordings.confermaVerifica($0.id) } }
                }
            }
        }
        .navigationTitle("Da verificare")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    /// Conferma prima di eliminare: la registrazione sparisce insieme a trascrizione, riassunto e metadati.
    func confermaEliminazione(_ registrazione: Binding<Registrazione?>, elimina: @escaping (Registrazione) -> Void) -> some View {
        alert("Eliminare la registrazione?",
              isPresented: Binding(get: { registrazione.wrappedValue != nil }, set: { if !$0 { registrazione.wrappedValue = nil } }),
              presenting: registrazione.wrappedValue) { r in
            Button("Elimina", role: .destructive) { elimina(r) }
            Button("Annulla", role: .cancel) {}
        } message: { r in
            Text("«\(r.titolo)» verrà eliminata dal dispositivo insieme a trascrizione e riassunto, se presenti. L'operazione non si può annullare.")
        }
    }
}

private struct RegistrazioneRow: View {
    let r: Registrazione
    var mostraInsegnamento = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if r.richiedeVerifica { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.caption) }
                Text(r.titolo).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            if mostraInsegnamento, let i = r.insegnamento { Text(i).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack(spacing: 8) {
                Text(r.creata.italiano(date: .abbreviated, time: .shortened))
                Text("· \(durata(r.durata))")
                if !r.segnalibri.isEmpty { Label("\(r.segnalibri.count)", systemImage: "bookmark.fill") }
                if !r.note.isEmpty { Image(systemName: "note.text") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Registratore

private struct RecorderCard: View {
    @Environment(AppModel.self) private var app
    @State private var scelto: String?          // codice insegnamento, nil = nessuno
    @State private var confermaAnnulla = false

    private var insegnamenti: [InsegnamentoAgenda] { app.agenda?.insegnamentiUtenteAttivati ?? [] }

    /// Suggerimento: lezione in corso o che inizia entro un'ora.
    private var suggerito: InsegnamentoAgenda? {
        let now = Date.now
        guard let l = app.lezioniUtente.value?.first(where: {
            !$0.annullato && $0.inizio.addingTimeInterval(-3600) <= now && now <= $0.fine
        }) else { return nil }
        return insegnamenti.first { $0.nome.matchKey == l.insegnamento.matchKey || $0.codice.hasPrefix(l.codiceInsegnamento + "_") }
    }

    var body: some View {
        let rec = app.recorder
        VStack(spacing: 18) {
            if rec.state == .idle {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Insegnamento").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Menu {
                        Picker("Insegnamento", selection: $scelto) {
                            Text("Nessun insegnamento").tag(String?.none)
                            ForEach(insegnamenti) { Text($0.nome).tag(Optional($0.codice)) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(insegnamenti.first { $0.codice == scelto }?.nome ?? "Nessun insegnamento")
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .tint(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await rec.start(in: app.recordings, insegnamento: insegnamenti.first { $0.codice == scelto }) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle")
                        Text("Avvia registrazione")
                    }
                    .foregroundStyle(.white)
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                VStack(spacing: 4) {
                    Text(rec.insegnamento?.nome ?? "Registrazione").font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                    Text(durata(rec.elapsed, precisa: true))
                        .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                    Text(rec.state == .paused ? "In pausa" : "Registrazione in corso")
                        .font(.caption).foregroundStyle(rec.state == .paused ? .orange : .red)
                }
                LevelMeter(level: rec.level)
                HStack(spacing: 28) {
                    CircleButton(system: "xmark", tint: .secondary) { confermaAnnulla = true }
                    CircleButton(system: rec.state == .paused ? "play.fill" : "pause.fill", tint: .orange) {
                        rec.state == .paused ? rec.resume() : rec.pause()
                    }
                    CircleButton(system: "stop.fill", tint: .red, big: true) {
                        if let r = rec.stop() { app.recordings.add(r) }
                    }
                    CircleButton(system: "bookmark.fill", tint: .accentColor) { rec.bookmark() }
                        .overlay(alignment: .topTrailing) {
                            if !rec.segnalibri.isEmpty {
                                Text("\(rec.segnalibri.count)").font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(4).background(.blue, in: Circle()).offset(x: 6, y: -6)
                            }
                        }
                }
            }
            if let e = rec.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .onAppear {
            if let r = app.registrazioneRichiesta { scelto = r.codice; app.registrazioneRichiesta = nil }
            if scelto == nil { scelto = suggerito?.codice }
        }
        .onChange(of: app.registrazioneRichiesta) { _, r in
            if let r { scelto = r.codice; app.registrazioneRichiesta = nil }
        }
        .onChange(of: app.lezioniUtente.updatedAt) { if scelto == nil { scelto = suggerito?.codice } }
        .confirmationDialog("Annullare la registrazione?", isPresented: $confermaAnnulla, titleVisibility: .visible) {
            Button("Elimina registrazione", role: .destructive) { rec.discard(in: app.recordings) }
        }
    }
}

private struct CircleButton: View {
    let system: String
    let tint: Color
    var big = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(big ? .title2 : .title3)
                .frame(width: big ? 64 : 48, height: big ? 64 : 48)
                .foregroundStyle(.white)
                .background(tint, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct LevelMeter: View {
    let level: Float
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.secondarySystemFill))
                Capsule().fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * CGFloat(level))
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Dettaglio

struct RegistrazioneDetailView: View {
    let id: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var player = AudioPlayer()
    @State private var confermaElimina = false

    /// Collegamento diretto all'archivio: trascrizioni e riassunti che finiscono in background restano coerenti.
    private func campo<T>(_ kp: WritableKeyPath<Registrazione, T>, _ vuoto: T) -> Binding<T> {
        Binding(get: { app.recordings.item(id)?[keyPath: kp] ?? vuoto },
                set: { v in
                    guard var r = app.recordings.item(id) else { return }
                    r[keyPath: kp] = v
                    app.recordings.update(r)
                })
    }

    private var insegnamento: Binding<String?> {
        Binding(get: { app.recordings.item(id)?.codiceInsegnamento },
                set: { codice in
                    guard var r = app.recordings.item(id) else { return }
                    r.codiceInsegnamento = codice
                    r.insegnamento = app.agenda?.insegnamentiUtenteAttivati.first { $0.codice == codice }?.nome
                        ?? (codice == nil ? nil : r.insegnamento)
                    app.recordings.update(r)
                })
    }

    var body: some View {
        Group {
            if let r = app.recordings.item(id) {
                Form {
                    if r.richiedeVerifica {
                        Section {
                            DatePicker("Inizio", selection: campo(\.creata, .now))
                                .environment(\.locale, Formats.it)
                            LabeledContent("Durata", value: durata(r.durata, precisa: true))
                            Button {
                                app.recordings.confermaVerifica(id)
                            } label: {
                                Label("I dati sono corretti", systemImage: "checkmark.circle")
                            }
                        } header: {
                            Text("Da verificare")
                        } footer: {
                            Text("Registrazione recuperata dai file: ascoltala e controlla data, ora e insegnamento (ricavati dal file audio e dalla lezione in orario a quell'ora). Correggi se serve, poi conferma.")
                        }
                    }
                    Section {
                        TextField("Titolo", text: campo(\.titolo, ""), axis: .vertical)
                        Picker("Insegnamento", selection: insegnamento) {
                            Text("Nessuno").tag(String?.none)
                            ForEach(app.agenda?.insegnamentiUtenteAttivati ?? []) { Text($0.nome).tag(Optional($0.codice)) }
                            if let c = r.codiceInsegnamento, !(app.agenda?.insegnamentiUtenteAttivati.contains { $0.codice == c } ?? false) {
                                Text(r.insegnamento ?? c).tag(Optional(c))
                            }
                        }
                        LabeledContent("Registrata", value: r.creata.italiano(date: .long, time: .shortened))
                    }
                    Section {
                        if player.illeggibile {
                            Label("Audio non leggibile: la registrazione è stata interrotta prima che il file venisse chiuso (ad esempio l'app è stata chiusa durante la registrazione).",
                                  systemImage: "waveform.slash")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            PlayerControls(player: player)
                        }
                    }
                    TrascrizioneSection(registrazione: r)
                    if AppleIntelligence.stato != .nonSupportata {
                        RiassuntoSection(registrazione: r)
                    }
                    if !r.segnalibri.isEmpty {
                        Section("Segnalibri") {
                            ForEach(Array(r.segnalibri.enumerated()), id: \.offset) { i, t in
                                Button { player.seek(to: t); player.play() } label: {
                                    Label("Segnalibro \(i + 1) · \(durata(t, precisa: true))", systemImage: "bookmark")
                                }
                            }
                            .onDelete { campo(\.segnalibri, []).wrappedValue.remove(atOffsets: $0) }
                        }
                    }
                    Section("Note") {
                        TextField("Appunti sulla lezione", text: campo(\.note, ""), axis: .vertical).lineLimit(4...)
                    }
                    Section {
                        ShareLink(item: app.recordings.url(for: r)) { Label("Condividi audio", systemImage: "square.and.arrow.up") }
                        Button("Elimina registrazione", role: .destructive) { confermaElimina = true }
                    }
                }
                .navigationTitle(r.titolo)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Registrazione non trovata", systemImage: "waveform.slash")
            }
        }
        .onAppear { if let r = app.recordings.item(id) { player.load(app.recordings.url(for: r)) } }
        .onDisappear { player.stop() }
        .confermaEliminazione(Binding(get: { confermaElimina ? app.recordings.item(id) : nil },
                                      set: { if $0 == nil { confermaElimina = false } })) { r in
            player.stop()
            app.eliminaRegistrazione(r)
            dismiss()
        }
    }
}

private struct PlayerControls: View {
    let player: AudioPlayer
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 16) {
            Slider(value: Binding(get: { scrubbing ?? player.currentTime }, set: { scrubbing = $0 }),
                   in: 0...max(player.duration, 1)) { editing in
                if !editing, let s = scrubbing { player.seek(to: s); scrubbing = nil }
            }
            HStack {
                Text(durata(scrubbing ?? player.currentTime, precisa: true))
                Spacer()
                Text("-" + durata(max(0, player.duration - (scrubbing ?? player.currentTime)), precisa: true))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 36) {
                Button { player.skip(-15) } label: { Image(systemName: "gobackward.15").font(.title2) }
                Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 52)) }
                Button { player.skip(30) } label: { Image(systemName: "goforward.30").font(.title2) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            Picker("Velocità", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { Text("\($0.formatted(.number.locale(Formats.it)))×").tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 10)
    }
}

private func durata(_ t: TimeInterval, precisa: Bool = false) -> String {
    let s = Int(t.rounded(.down))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if precisa { return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec) }
    return h > 0 ? "\(h) h \(m) min" : m > 0 ? "\(m) min" : "\(sec) s"
}
