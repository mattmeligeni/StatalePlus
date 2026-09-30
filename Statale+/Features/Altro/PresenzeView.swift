import SwiftUI

/// EasyBadge: registrazione presenza (codice lezione / QR) e percentuali di frequenza.
struct PresenzeView: View {
    @Environment(AppModel.self) private var app
    @State private var codice = ""
    @State private var showScanner = false
    @State private var inviando = false
    @State private var risposta: TimbraturaResult?
    @State private var erroreInvio: String?
    @FocusState private var focus: Bool

    var body: some View {
        List {
            Section {
                if let l = app.presenzaTarget {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.insegnamento).font(.subheadline.weight(.semibold))
                        Text("\(Formats.time(l.inizio)) – \(Formats.time(l.fine)) · \(l.aula)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("Codice lezione", text: $codice)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focus)
                        .submitLabel(.send)
                        .onSubmit { Task { await invia() } }
                    Button { showScanner = true } label: {
                        Image(systemName: "qrcode.viewfinder").font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Scansiona QR")
                }
                Button {
                    Task { await invia() }
                } label: {
                    HStack { Spacer(); if inviando { ProgressView() } else { Text("Registra presenza").bold() }; Spacer() }
                }
                .disabled(inviando || codice.trimmed.isEmpty || app.studente == nil)
                if let r = risposta {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(r.ok ? "Presenza registrata" : "Risposta: \(r.result)",
                              systemImage: r.ok ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(r.ok ? .green : .orange)
                        if !r.message.isEmpty { Text(r.message).font(.callout) }
                    }
                }
                if let erroreInvio { Label(erroreInvio, systemImage: "wifi.exclamationmark").foregroundStyle(.red).font(.callout) }
            } header: {
                Text("Registra presenza")
            } footer: {
                if let m = app.studente?.matricolaAPI { Text("Matricola \(m)") }
            }

            LiveSection(title: "Frequenza", live: app.frequenze, retry: load) { list in
                if list.isEmpty { Text("Nessun corso con rilevazione presenze").foregroundStyle(.secondary) }
                ForEach(list) { f in
                    NavigationLink { SlotListView(frequenza: f, slot: (app.slotPresenze.value ?? []).filter { $0.codiceCorso == f.codice }) } label: {
                        FrequenzaRow(f: f)
                    }
                }
            }
            UpdatedFooter(date: app.frequenze.updatedAt).listRowBackground(Color.clear)
        }
        .navigationTitle("Presenze")
        .refreshable { app.segnaRefresh(); await load() }
        .task { if app.frequenze.updatedAt == nil { await load() } }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { payload in
                codice = QRLezione.codice(from: payload)
            }
        }
    }

    private func load() async { await app.loadPresenze() }

    private func invia() async {
        guard let m = app.studente?.matricolaAPI, !codice.trimmed.isEmpty else { return }
        focus = false
        inviando = true
        erroreInvio = nil
        risposta = nil
        defer { inviando = false }
        do {
            let r = try await app.services.easyBadge.timbra(TimbraturaRequest(matricola: m, codiceLezione: codice.trimmed))
            risposta = r
            if r.ok {
                app.registraPresenzaConfermata()
                await load()
            }
        } catch {
            erroreInvio = app.message(error)
        }
    }
}

private struct FrequenzaRow: View {
    let f: Frequenza
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(f.nome).font(.subheadline.weight(.semibold))
            if f.nascondiConteggi {
                Text("Conteggi non visibili per questo corso").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(value: min(f.minutiFatti, f.minutiTotali), total: max(f.minutiTotali, 1))
                    .tint(f.sogliaRaggiunta ? .green : .accentColor)
                HStack {
                    Text("\(ore(f.minutiFatti)) su \(ore(f.minutiTotali))")
                    Spacer()
                    Text("soglia \(Int(f.soglia * 100))% = \(ore(f.minutiSoglia))")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// I campi "Ore…" di EasyBadge sono minuti.
private func ore(_ minuti: Double) -> String {
    let m = Int(minuti.rounded())
    return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
}

private struct SlotListView: View {
    let frequenza: Frequenza
    let slot: [SlotLezione]
    var body: some View {
        List(slot) { s in
            HStack {
                VStack(alignment: .leading) {
                    Text(s.inizio.formatted(.dateTime.weekday(.abbreviated).day().month().locale(Formats.it)))
                    Text("\(Formats.time(s.inizio)) – \(Formats.time(s.fine))").font(.caption).foregroundStyle(.secondary)
                    TimeStatusBadge(inizio: s.inizio, fine: s.fine)
                }
                Spacer()
                if s.presenza {
                    Label("Presente", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if s.svolta || s.fine < .now {
                    Label("Assente", systemImage: "xmark.circle").foregroundStyle(.secondary)
                } else {
                    Text("In programma").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .navigationTitle(frequenza.nome)
        .navigationBarTitleDisplayMode(.inline)
    }
}
