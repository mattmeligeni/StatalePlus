import SwiftUI

// MARK: - Sezioni nel dettaglio

/// Trascrizione con Speech: avvio, avanzamento, anteprima e accesso al testo completo.
struct TrascrizioneSection: View {
    let registrazione: Registrazione
    @Environment(AppModel.self) private var app
    @State private var anteprima: String?
    @State private var mostraMotori = false
    @AppStorage("motoreTrascrizione") private var motore = MotoreTrascrizione.apple.rawValue

    var body: some View {
        let id = registrazione.id
        Section {
            if let s = app.elaborazioni.stato(.trascrizione, id) {
                StatoElaborazione(stato: s) { app.elaborazioni.annulla(.trascrizione, id) }
            } else if registrazione.trascrittaIl != nil {
                if let anteprima { Text(anteprima).font(.callout).lineLimit(4).foregroundStyle(.secondary) }
                NavigationLink { TrascrizioneView(id: id) } label: {
                    Label("Leggi e modifica la trascrizione", systemImage: "text.alignleft")
                }
            } else if let motivo = LimitiElaborazione.bloccoTrascrizione(registrazione) {
                Label(motivo, systemImage: "clock.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
            } else {
                Button { app.elaborazioni.trascrivi(registrazione, in: app.recordings) } label: {
                    Label("Trascrivi registrazione", systemImage: "waveform.badge.magnifyingglass")
                }
            }
            if let e = app.elaborazioni.errori[id], app.elaborazioni.stato(.trascrizione, id) == nil, registrazione.trascrittaIl == nil {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Trascrizione")
        } footer: {
            if registrazione.trascrittaIl == nil, LimitiElaborazione.bloccoTrascrizione(registrazione) == nil,
               app.elaborazioni.stato(.trascrizione, id) == nil {
                VStack(alignment: .leading, spacing: 6) {
                    if motore == MotoreTrascrizione.parakeet.rawValue, ParakeetLocale.installato {
                        Text("Trascrizione con Parakeet.")
                    } else {
                        Text("Riconoscimento vocale di Apple. Sono disponibili modelli più precisi.")
                    }
                    Button("Scegli il modello") { mostraMotori = true }
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $mostraMotori) {
            NavigationStack {
                ImpostazioniTrascrizioneView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { mostraMotori = false } } }
            }
        }
        .task(id: registrazione.trascrittaIl) {
            anteprima = app.recordings.trascrizione(id).map { String($0.prefix(400)) }
        }
    }
}

/// Riassunto con Apple Intelligence o Qwen (visibile se almeno uno dei due può funzionare su questo iPhone).
struct RiassuntoSection: View {
    let registrazione: Registrazione
    @Environment(AppModel.self) private var app
    @State private var testo: String?
    @State private var trascrizione: String?

    var body: some View {
        let id = registrazione.id
        let blocco = LimitiElaborazione.bloccoRiassunto(registrazione, trascrizione: trascrizione)
        Section {
            switch MotoreRiassunto.disponibile != nil ? .disponibile : AppleIntelligence.stato {
            case .nonAttiva:
                Label("Attiva Apple Intelligence in Impostazioni per generare i riassunti delle lezioni.", systemImage: "apple.intelligence")
                    .font(.callout)
            case .inPreparazione:
                Label("Apple Intelligence sta scaricando il modello. Riprova tra poco.", systemImage: "arrow.down.circle")
                    .font(.callout)
            case .nonSupportata:
                EmptyView()
            case .disponibile:
                if let s = app.elaborazioni.stato(.riassunto, id) {
                    StatoElaborazione(stato: s) { app.elaborazioni.annulla(.riassunto, id) }
                } else if registrazione.riassuntoIl != nil, let testo {
                    MarkdownTesto(markdown: testo).lineLimit(8)
                    NavigationLink { RiassuntoView(id: id) } label: { Label("Apri riassunto", systemImage: "doc.text.magnifyingglass") }
                } else if let blocco {
                    Label(blocco, systemImage: "clock.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button { app.elaborazioni.riassumi(registrazione, in: app.recordings) } label: {
                        Label("Genera riassunto", systemImage: "sparkles")
                    }
                }
            }
        } header: {
            Label("Riassunto", systemImage: "apple.intelligence")
        } footer: {
            if let motore = MotoreRiassunto.disponibile, registrazione.riassuntoIl == nil, blocco == nil {
                Text("Con \(motore.nome), solo dal testo trascritto: riassunto, punti chiave e domande di ripasso.")
            }
            if let e = app.elaborazioni.errori[id], app.elaborazioni.stato(.riassunto, id) == nil, registrazione.trascrittaIl != nil {
                Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .task(id: registrazione.riassuntoIl) { testo = app.recordings.riassunto(id) }
        .task(id: registrazione.trascrittaIl) { trascrizione = app.recordings.trascrizione(id) }
    }
}

private struct StatoElaborazione: View {
    let stato: ElaborazioniAudio.Stato
    let annulla: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: stato.progresso) {
                Text(stato.messaggio).font(.callout)
            } currentValueLabel: {
                Text(stato.progresso.formatted(.percent.precision(.fractionLength(0)))).font(.caption.monospacedDigit())
            }
            if !stato.inPausa {
                Text(stato.motore == MotoreRiassunto.qwen.nome
                     ? "Qwen lavora con l'app aperta: se esci si mette in pausa e riprende quando torni."
                     : NotaBackground.testo).font(.caption).foregroundStyle(.secondary)
            }
            Button("Annulla", role: .destructive, action: annulla).font(.callout).buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Trascrizione completa

/// Testo completo modificabile, con Writing Tools (iOS 18+) per correggere, riscrivere o riassumere.
struct TrascrizioneView: View {
    let id: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var testo = ""
    @State private var caricato = false
    @State private var confermaRifai = false
    @State private var confermaElimina = false

    var body: some View {
        TextEditor(text: $testo)
            .font(.body)
            .strumentiScrittura()
            .padding(.horizontal, 8)
            .tastieraConChiudi()
            .navigationTitle("Trascrizione")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Text("\(testo.split(whereSeparator: \.isWhitespace).count) parole")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(6).background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: testo) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { UIPasteboard.general.string = testo } label: { Label("Copia tutto", systemImage: "doc.on.doc") }
                        Button { confermaRifai = true } label: { Label("Trascrivi di nuovo", systemImage: "arrow.clockwise") }
                        Button(role: .destructive) { confermaElimina = true } label: { Label("Elimina trascrizione", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onAppear {
                guard !caricato else { return }
                testo = app.recordings.trascrizione(id) ?? ""
                caricato = true
            }
            .task(id: testo) {
                // Salvataggio con debounce mentre si modifica.
                guard caricato else { return }
                try? await Task.sleep(for: .seconds(1))
                salva()
            }
            .onDisappear { salva() }
            .confirmationDialog("Trascrivere di nuovo?", isPresented: $confermaRifai, titleVisibility: .visible) {
                Button("Trascrivi di nuovo", role: .destructive) {
                    caricato = false
                    app.recordings.salvaTrascrizione(id, nil)
                    if let r = app.recordings.item(id) { app.elaborazioni.trascrivi(r, in: app.recordings) }
                    dismiss()
                }
            } message: { Text("Le modifiche fatte a mano andranno perse.") }
            .confirmationDialog("Eliminare la trascrizione?", isPresented: $confermaElimina, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    caricato = false
                    app.recordings.salvaTrascrizione(id, nil)
                    dismiss()
                }
            }
    }

    private func salva() {
        guard caricato, testo != app.recordings.trascrizione(id) else { return }
        app.recordings.salvaTrascrizione(id, testo)
    }
}

// MARK: - Riassunto completo

struct RiassuntoView: View {
    let id: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var testo = ""
    @State private var caricato = false
    @State private var modifica = false
    @State private var pdf: URL?

    var body: some View {
        Group {
            if modifica {
                TextEditor(text: $testo)
                    .font(.body.monospaced())
                    .strumentiScrittura()
                    .padding(.horizontal, 8)
                    .tastieraConChiudi()
            } else {
                ScrollView {
                    MarkdownTesto(markdown: testo)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Riassunto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(modifica ? "Fine" : "Modifica") {
                    if modifica { salva() }
                    modifica.toggle()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let pdf {
                        ShareLink(item: pdf) { Label("Condividi o stampa il PDF", systemImage: "printer") }
                    }
                    Button { UIPasteboard.general.string = testo } label: { Label("Copia il testo", systemImage: "doc.on.doc") }
                    Button {
                        if let r = app.recordings.item(id) { app.elaborazioni.riassumi(r, in: app.recordings) }
                        dismiss()
                    } label: { Label("Genera di nuovo", systemImage: "sparkles") }
                    Button(role: .destructive) {
                        caricato = false
                        app.recordings.salvaRiassunto(id, nil)
                        dismiss()
                    } label: { Label("Elimina riassunto", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear {
            guard !caricato else { return }
            testo = app.recordings.riassunto(id) ?? ""
            caricato = true
        }
        .task(id: modifica ? "" : testo) {
            // PDF rigenerato quando il testo cambia (non durante la modifica).
            guard !modifica, !testo.isEmpty, let r = app.recordings.item(id) else { return }
            pdf = PDFRiassunto.crea(markdown: testo, titolo: r.titolo,
                                    sottotitolo: [r.insegnamento, r.creata.italiano(date: .long, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
        }
        .onDisappear { salva() }
    }

    private func salva() {
        guard caricato, testo != app.recordings.riassunto(id) else { return }
        app.recordings.salvaRiassunto(id, testo)
    }
}

// MARK: - Supporto

/// Rendering essenziale del Markdown dei riassunti: titoli `##`, elenchi puntati/numerati, grassetto/corsivo inline.
struct MarkdownTesto: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, riga in
                let r = riga.trimmingCharacters(in: .whitespaces)
                if r.hasPrefix("###") {
                    Text(inline(r.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                        .font(.subheadline.weight(.semibold)).padding(.top, 4)
                } else if r.hasPrefix("#") {
                    Text(inline(r.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                        .font(.title3.bold()).padding(.top, 10)
                } else if r.hasPrefix("- ") || r.hasPrefix("* ") || r.hasPrefix("• ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(String(r.dropFirst(2))))
                    }
                } else if let m = r.firstMatch(#"^(\d+)[.)]\s+(.*)$"#, group: 2), let n = r.firstMatch(#"^(\d+)[.)]"#) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n).").monospacedDigit()
                        Text(inline(m))
                    }
                } else if !r.isEmpty {
                    Text(inline(r))
                }
            }
        }
        .font(.callout)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

extension View {
    /// Writing Tools completi (riscrittura, correzione, riassunto) su iOS 18+.
    @ViewBuilder
    func strumentiScrittura() -> some View {
        if #available(iOS 18.0, *) { writingToolsBehavior(.complete) } else { self }
    }
}
