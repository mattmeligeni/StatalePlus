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
    @AppStorage("sogliaFrequenzaManuale") private var sogliaManuale = 0

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
                if let m = app.studente?.matricola { Text("Matricola \(m.uppercased())") }
            }

            LiveSection(title: "Frequenza", live: app.frequenze, retry: load) { list in
                if list.isEmpty { Text("Nessun corso con rilevazione presenze").foregroundStyle(.secondary) }
                ForEach(list) { f in
                    let soglia = app.soglia(per: f, manuale: sogliaManuale).valore
                    NavigationLink {
                        SlotListView(frequenza: f, soglia: soglia, slot: (app.slotPresenze.value ?? []).filter { $0.codiceCorso == f.codice })
                    } label: {
                        FrequenzaRow(f: f, soglia: soglia)
                    }
                }
            }
            if let f = app.frequenze.value?.first {
                Section {
                    EmptyView()
                } footer: {
                    fonteSoglia(app.soglia(per: f, manuale: sogliaManuale).fonte)
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

    @ViewBuilder
    private func fonteSoglia(_ fonte: FonteSoglia) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Soglia di frequenza \(fonte.descrizione). Si può cambiare in Impostazioni.")
            if fonte == .manifesto, let url = app.obbligoFrequenza?.url {
                Link("Apri il manifesto degli studi", destination: url)
            }
        }
        .font(.footnote)
    }

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
    let soglia: Double
    var body: some View {
        let minutiSoglia = f.minutiTotali * soglia
        let raggiunta = minutiSoglia > 0 && f.minutiFatti >= minutiSoglia
        VStack(alignment: .leading, spacing: 6) {
            Text(f.nome).font(.subheadline.weight(.semibold))
            if f.nascondiConteggi {
                Text("Conteggi non visibili per questo corso").font(.caption).foregroundStyle(.secondary)
            } else {
                BarraFrequenza(frazione: f.minutiTotali > 0 ? f.minutiFatti / f.minutiTotali : 0, soglia: soglia, raggiunta: raggiunta)
                HStack {
                    Text("\(ore(f.minutiFatti)) su \(ore(f.minutiTotali))")
                    Spacer()
                    Text(raggiunta ? "soglia \(Int((soglia * 100).rounded()))% raggiunta"
                                   : "soglia \(Int((soglia * 100).rounded()))% = \(ore(minutiSoglia))")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Barra di avanzamento con una tacca sulla soglia richiesta.
private struct BarraFrequenza: View {
    let frazione: Double
    let soglia: Double
    let raggiunta: Bool

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill))
                Capsule().fill(raggiunta ? Color.green : Color.accentColor)
                    .frame(width: g.size.width * min(max(frazione, 0), 1))
                Rectangle().fill(Color.primary.opacity(0.55))
                    .frame(width: 2, height: 10)
                    .offset(x: g.size.width * min(max(soglia, 0), 1) - 1)
            }
        }
        .frame(height: 6)
        .padding(.vertical, 2)
        .accessibilityElement()
        .accessibilityLabel("Frequenza \(Int((frazione * 100).rounded())) per cento, soglia \(Int((soglia * 100).rounded())) per cento")
    }
}

/// I campi "Ore…" di EasyBadge sono minuti.
private func ore(_ minuti: Double) -> String {
    let m = Int(minuti.rounded())
    return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
}

private struct SlotListView: View {
    let frequenza: Frequenza
    let soglia: Double
    let slot: [SlotLezione]

    var body: some View {
        let minutiSoglia = frequenza.minutiTotali * soglia
        let mancanti = max(minutiSoglia - frequenza.minutiFatti, 0)
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(frequenza.nome).font(.headline)
                    if !frequenza.nascondiConteggi {
                        BarraFrequenza(frazione: frequenza.minutiTotali > 0 ? frequenza.minutiFatti / frequenza.minutiTotali : 0,
                                       soglia: soglia, raggiunta: mancanti == 0 && minutiSoglia > 0)
                        Text(mancanti == 0
                             ? "\(ore(frequenza.minutiFatti)) frequentate su \(ore(frequenza.minutiTotali)): soglia del \(Int((soglia * 100).rounded()))% raggiunta."
                             : "\(ore(frequenza.minutiFatti)) frequentate su \(ore(frequenza.minutiTotali)): mancano \(ore(mancanti)) per la soglia del \(Int((soglia * 100).rounded()))%.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Lezioni") {
                ForEach(slot) { s in
                    let futura = s.inizio > .now
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.inizio.formatted(.dateTime.weekday(.abbreviated).day().month().locale(Formats.it)))
                            Text("\(Formats.time(s.inizio)) – \(Formats.time(s.fine))").font(.caption).foregroundStyle(.secondary)
                            TimeStatusBadge(inizio: s.inizio, fine: s.fine)
                        }
                        Spacer()
                        if s.presenza {
                            HStack(spacing: 4) { Image(systemName: "checkmark.circle.fill"); Text("Presente") }
                                .foregroundStyle(.green)
                        } else if s.svolta || s.fine < .now {
                            HStack(spacing: 4) { Image(systemName: "xmark.circle"); Text("Assente") }
                                .foregroundStyle(.secondary)
                        } else {
                            Text("In programma").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.subheadline)
                    .opacity(futura ? 0.6 : 1)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                }
            }
        }
        .navigationTitle("Frequenza")
        .navigationBarTitleDisplayMode(.inline)
    }
}
