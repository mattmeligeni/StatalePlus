import SwiftUI

/// Esami: calendario appelli (API Agenda, corso e anno selezionabili) + iscrizioni (SIFA).
struct EsamiView: View {
    private enum Tab: String, CaseIterable { case calendario = "Calendario", iscrizioni = "Iscrizioni" }
    @State private var tab: Tab = .calendario
    @State private var showCorsi = false
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Picker("Vista", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            switch tab {
            case .calendario: CalendarioAppelliView()
            case .iscrizioni: IscrizioniSifaView()
            }
        }
        .navigationTitle("Esami")
        .toolbar {
            if tab == .calendario {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showCorsi = true } label: { Label("Cambia corso…", systemImage: "building.columns") }
                        if let a = app.agenda, a.corsoEsami.cdl.valore != a.mioCorsoEsami.cdl.valore {
                            Button {
                                app.setCorsoEsami(a.mioCorsoEsami)
                                Task { await app.loadAppelli() }
                            } label: { Label("Torna al mio corso", systemImage: "person.crop.circle") }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
        }
        .sheet(isPresented: $showCorsi) {
            CorsoPicker(titolo: "Corso per gli appelli", albero: app.alberoEsami, load: app.loadAlberoEsami,
                        attuale: app.agenda?.corsoEsami, mio: app.agenda?.mioCorsoEsami) { c in
                app.setCorsoEsami(c)
                Task { await app.loadAppelli() }
            }
        }
    }
}

private struct CalendarioAppelliView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            if let a = app.agenda {
                Section {
                    PillPicker(items: a.corsoEsami.cdl.periodi, selected: app.annoEsami, title: { p in
                        p.valore == "0" ? "Anno 0" : "\(p.valore)° anno"
                    }) { p in
                        app.setAnnoEsami(p.valore)
                        Task { await app.loadAppelli() }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text(a.corsoEsami.cdl.label).textCase(nil)
                }
            }
            LiveSection(title: "Prossimi appelli", live: app.appelli, retry: app.loadAppelli) { appelli in
                let lista = appelli.filter { !$0.passato || $0.inizio > .now.addingTimeInterval(-6 * 3600) }
                if lista.isEmpty { Text("Nessun appello in calendario").foregroundStyle(.secondary) }
                ForEach(lista) { AppelloRow(appello: $0) }
            }
            UpdatedFooter(date: app.appelli.updatedAt).listRowBackground(Color.clear)
        }
        .refreshable { await app.loadAppelli() }
        .task { if app.appelli.updatedAt == nil { await app.loadAppelli() } }
    }
}

private struct IscrizioniSifaView: View {
    @Environment(AppModel.self) private var app
    @State private var esiti = Live<TabellaSifa>()
    @State private var showIscrizione = false

    var body: some View {
        List {
            Section {
                Button { showIscrizione = true } label: {
                    Label("Iscriviti a un appello", systemImage: "square.and.pencil")
                }
            }
            LiveSection(title: "Prenotazioni confermate", live: app.prenotazioni, retry: app.loadPrenotazioni) { tab in
                let prenotazioni = Prenotazione.from(tab)
                if !prenotazioni.isEmpty {
                    ForEach(prenotazioni) { p in
                        let match = app.appelliUtente.value?.first {
                            Formats.calendar.isDate($0.inizio, inSameDayAs: p.data) && $0.insegnamento.matchKey.contains(p.esame.matchKey)
                        }
                        PrenotazioneRow(prenotazione: p, appello: match)
                    }
                } else {
                    TabellaSifaRows(tabella: tab)
                }
            }
            LiveSection(title: "Esiti da accettare", live: esiti, retry: loadEsiti) { TabellaSifaRows(tabella: $0) }
        }
        .refreshable {
            async let a: Void = app.loadPrenotazioni()
            async let b: Void = loadEsiti()
            _ = await (a, b)
        }
        .task {
            // In serie: la sessione Wicket è stateful e condivisa.
            if app.prenotazioni.updatedAt == nil { await app.loadPrenotazioni() }
            await esiti.loadIfNeeded { try await app.services.sifa.esitiFinali() }
            if app.appelliUtente.updatedAt == nil { await app.loadAppelliUtente() }
        }
        .sheet(isPresented: $showIscrizione) { IscrizioneAppelloSheet() }
    }

    private func loadEsiti() async { await esiti.load { try await app.services.sifa.esitiFinali() } }
}

/// Replica "Esami del tuo corso di studio" di SIFA: ricerca per descrizione, tabella Codice/Descrizione/Crediti
/// e pulsante "Iscrizione" per riga.
struct IscrizioneAppelloSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var esami = Live<[EsameIscrivibile]>()
    @State private var descrizione = ""
    @State private var conferma: EsameIscrivibile?
    @State private var inCorso: String?
    @State private var esito: String?

    private func filtrati(_ list: [EsameIscrivibile]) -> [EsameIscrivibile] {
        let q = descrizione.trimmed
        return q.isEmpty ? list : list.filter { $0.descrizione.localizedCaseInsensitiveContains(q) || $0.codice.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let esito {
                    Section { Label(esito, systemImage: "info.circle").font(.callout) }
                }
                LiveSection(title: "Esami del tuo corso di studio", live: esami, retry: load) { list in
                    let rows = filtrati(list)
                    if rows.isEmpty { Text("Nessun esame trovato").foregroundStyle(.secondary) }
                    ForEach(rows) { e in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.descrizione).font(.subheadline)
                                HStack {
                                    Text(e.codice).font(.caption.monospaced())
                                    Text("· \(e.crediti) CFU").font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                conferma = e
                            } label: {
                                if inCorso == e.codice { ProgressView().controlSize(.small) } else { Text("Iscrizione") }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(inCorso != nil)
                        }
                    }
                }
            }
            .searchable(text: $descrizione, placement: .navigationBarDrawer(displayMode: .always), prompt: "Descrizione")
            .navigationTitle("Iscrizione agli appelli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .refreshable { await load() }
            .task { await esami.loadIfNeeded { try await app.services.sifa.esamiIscrivibili() } }
            .confirmationDialog(conferma.map { "Iscriversi a \($0.descrizione.capitalized)?" } ?? "",
                                isPresented: Binding(get: { conferma != nil }, set: { if !$0 { conferma = nil } }),
                                titleVisibility: .visible) {
                if let e = conferma {
                    Button("Iscrizione") { Task { await iscrivi(e) } }
                }
            }
        }
    }

    private func load() async { await esami.load { try await app.services.sifa.esamiIscrivibili() } }

    private func iscrivi(_ e: EsameIscrivibile) async {
        inCorso = e.codice
        defer { inCorso = nil }
        do {
            esito = try await app.services.sifa.iscrivi(e)
            await app.loadPrenotazioni()
        } catch {
            esito = app.message(error)
        }
    }
}

struct TabellaSifaRows: View {
    let tabella: TabellaSifa
    var body: some View {
        if tabella.vuota {
            Text(tabella.messaggio ?? "Nessun elemento").foregroundStyle(.secondary)
        } else {
            ForEach(Array(tabella.righe.enumerated()), id: \.offset) { _, riga in
                VStack(alignment: .leading) {
                    ForEach(tabella.colonne.isEmpty ? riga.keys.sorted() : tabella.colonne, id: \.self) { k in
                        if let v = riga[k], !v.isEmpty { LabeledContent(k, value: v).font(.caption) }
                    }
                }
            }
        }
    }
}
