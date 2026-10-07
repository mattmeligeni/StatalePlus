import SwiftUI

/// EasyBadge: registrazione presenza (codice lezione / QR) e percentuali di frequenza.
struct PresenzeView: View {
    @Environment(AppModel.self) private var app
    @State private var codice = ""
    @State private var matricola = ""
    /// Matricola effettivamente inviata all'ultima timbratura, mostrata nei feedback anche dopo il reset della textfield.
    @State private var matricolaUsata = ""
    @State private var showScanner = false
    @State private var inviando = false
    @State private var risposta: TimbraturaResult?
    @State private var erroreInvio: String?
    /// Esito "ok" o "failure": schermata a tutto schermo, impossibile da non notare (gli utenti riprovavano per sicurezza).
    @State private var esitoGrande: TimbraturaResult?
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
                // Modificabile: parte con la matricola del profilo ma l'utente può sceglierne un'altra.
                LabeledContent("Matricola") {
                    TextField("Matricola", text: $matricola)
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                .accessibilityHint("Modificabile: la presenza viene registrata con la matricola indicata qui")
                HStack {
                    CampoCodice(segnaposto: "Codice lezione", testo: $codice, invio: .send) { Task { await invia() } }
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
                .disabled(inviando || codice.trimmed.isEmpty || matricola.trimmed.isEmpty || app.studente == nil)
            } header: {
                Text("Registra presenza")
            } footer: {
                if app.studente != nil { Text("La presenza viene registrata con la matricola indicata.") }
            }

            // Esito in una sezione a parte: la riga del pulsante non cambia forma né posizione.
            if let r = risposta {
                Section {
                    EsitoTimbratura(simbolo: simbolo(r), colore: colore(r), titolo: r.titolo, testo: r.spiegazione,
                                    server: r.esito == .sconosciuto ? nil : r.message,
                                    matricola: matricolaUsata.isEmpty ? nil : matricolaUsata)
                }
            } else if let erroreInvio {
                Section {
                    EsitoTimbratura(simbolo: "wifi.exclamationmark", colore: .red, titolo: "Richiesta non inviata",
                                    testo: erroreInvio, server: nil,
                                    matricola: matricolaUsata.isEmpty ? nil : matricolaUsata)
                }
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
                let fonte = app.soglia(per: f, manuale: sogliaManuale).fonte
                Section {
                    if fonte == .manifesto, let url = app.obbligoFrequenza?.url {
                        DocumentoPDFRow(titolo: "Manifesto degli studi", simbolo: "doc.text", url: url)
                    }
                } footer: {
                    Text("Soglia di frequenza \(fonte.descrizione). Si può cambiare in Impostazioni.")
                }
            }
            UpdatedFooter(date: app.frequenze.updatedAt).listRowBackground(Color.clear)
        }
        .tastieraConChiudi()
        .navigationTitle("Presenze")
        .refreshable { app.segnaRefresh(); await load() }
        .task {
            if matricola.isEmpty, let m = app.studente?.matricola {
                matricola = m.uppercased()
            }
            if app.frequenze.updatedAt == nil { await load() }
        }
        .fullScreenCover(item: $esitoGrande) { r in
            EsitoPresenzaSchermata(esito: r, lezione: app.presenzaTarget?.insegnamento,
                                   matricola: matricolaUsata.isEmpty ? nil : matricolaUsata) {
                esitoGrande = nil
            } riprova: {
                esitoGrande = nil
                codice = ""
                Task { try? await Task.sleep(for: .milliseconds(400)); showScanner = true }
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { payload in
                codice = QRLezione.codice(from: payload)
                // Il QR in aula cambia di continuo: si invia subito, prima che il codice scada.
                Task { await invia() }
            }
        }
    }

    private func load() async { await app.loadPresenze() }

    private func simbolo(_ r: TimbraturaResult) -> String {
        switch r.esito {
        case .registrata: "checkmark.seal.fill"
        case .giaRegistrata: "checkmark.circle.fill"
        case .fallita: "xmark.octagon.fill"
        case .sconosciuto: "questionmark.circle.fill"
        }
    }

    private func colore(_ r: TimbraturaResult) -> Color {
        switch r.esito {
        case .registrata, .giaRegistrata: .green
        case .fallita: .red
        case .sconosciuto: .orange
        }
    }

    /// Riporta la textfield matricola al valore dell'utente loggato.
    private func resetMatricola() {
        matricola = app.studente?.matricola.uppercased() ?? ""
    }

    private func invia() async {
        guard !inviando, app.studente != nil,
              !matricola.trimmed.isEmpty, !codice.trimmed.isEmpty else { return }
        Tastiera.chiudi()
        let matricolaInvio = matricola.trimmed
        matricolaUsata = matricolaInvio
        inviando = true
        erroreInvio = nil
        risposta = nil
        defer {
            inviando = false
            // Dopo l'invio si torna alla matricola dell'utente (quella usata resta visibile nei feedback).
            resetMatricola()
        }
        do {
            let r = try await app.services.easyBadge.timbra(TimbraturaRequest(matricola: matricolaInvio, codiceLezione: codice.trimmed))
            risposta = r
            if r.esito == .registrata || r.esito == .fallita {
                UINotificationFeedbackGenerator().notificationOccurred(r.esito == .registrata ? .success : .error)
                esitoGrande = r
            }
            if r.ok {
                app.registraPresenzaConfermata()
                await load()
            }
        } catch {
            erroreInvio = app.message(error)
        }
    }
}

/// Esito della timbratura a tutto schermo: verde con sigillo se registrata, rosso se fallita.
private struct EsitoPresenzaSchermata: View {
    let esito: TimbraturaResult
    let lezione: String?
    let matricola: String?
    let chiudi: () -> Void
    let riprova: () -> Void

    private var riuscita: Bool { esito.esito == .registrata }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: riuscita ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.system(size: 110, weight: .semibold))
                .symbolEffect(.bounce, value: riuscita)
            Text(riuscita ? "Presenza registrata" : "Presenza NON registrata")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            if let lezione {
                Text(lezione).font(.title3.weight(.medium)).multilineTextAlignment(.center).opacity(0.9)
            }
            if let matricola, !matricola.isEmpty {
                Text("Matricola: \(matricola)")
                    .font(.callout.monospaced())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            Text(riuscita ? "Non serve ripetere la scansione: la tua presenza è già sul server dell'Università."
                          : esito.spiegazione)
                .font(.body)
                .multilineTextAlignment(.center)
                .opacity(0.9)
                .padding(.horizontal)
            Spacer()
            VStack(spacing: 12) {
                if !riuscita {
                    Button(action: riprova) {
                        Label("Scansiona di nuovo", systemImage: "qrcode.viewfinder")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.red)
                }
                Button(action: chiudi) {
                    Text(riuscita ? "Fatto" : "Chiudi").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((riuscita ? Color.green : Color.red).gradient)
        .accessibilityElement(children: .contain)
    }
}

private struct EsitoTimbratura: View {
    let simbolo: String
    let colore: Color
    let titolo: String
    let testo: String
    let server: String?
    var matricola: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: simbolo).foregroundStyle(colore)
            VStack(alignment: .leading, spacing: 4) {
                Text(titolo).font(.subheadline.bold()).foregroundStyle(colore)
                Text(testo).font(.callout)
                if let matricola, !matricola.isEmpty {
                    Text("Matricola: \(matricola)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if let server, !server.isEmpty {
                    Text("Messaggio del server: \(server)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
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
