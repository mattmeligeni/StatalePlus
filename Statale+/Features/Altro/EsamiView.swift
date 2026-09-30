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
            .padding(.bottom, 12)
            switch tab {
            case .calendario: CalendarioAppelliView()
            case .iscrizioni: IscrizioniSifaView()
            }
        }
        .background(Color(.systemGroupedBackground))
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
    @State private var showVaiA = false

    /// Appelli raggruppati per settimana (lunedì–domenica).
    private func settimane(_ appelli: [Appello]) -> [(inizio: Date, appelli: [Appello])] {
        Dictionary(grouping: appelli) { Formats.inizioSettimana($0.inizio) }
            .map { ($0.key, $0.value.sorted { $0.inizio < $1.inizio }) }
            .sorted { $0.0 < $1.0 }
    }

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
                    .listRowSeparator(.hidden)
                } header: {
                    Text(Testo.nomeCorso(a.corsoEsami.cdl.label)).textCase(nil)
                }
                .listSectionSpacing(6)
                Section {
                    HStack {
                        Button { showVaiA = true } label: { Label("Vai a data", systemImage: "calendar.badge.clock") }
                        Spacer()
                        if let da = app.appelliDa {
                            Text("Dal \(da.formatted(.dateTime.day().month(.wide).year().locale(Formats.it)))")
                                .foregroundStyle(.secondary)
                            Button("Oggi") { app.setAppelliDa(nil); Task { await app.loadAppelli() } }
                        }
                    }
                    .font(.callout)
                    .buttonStyle(.borderless)
                }
            }
            if let error = app.appelli.error {
                ErrorRow(message: error) { await app.loadAppelli() }
            }
            if let appelli = app.appelli.value {
                // Da oggi: si nascondono gli appelli già passati; con "Vai a data" si mostra tutto dalla settimana scelta.
                let lista = app.appelliDa == nil ? appelli.filter { !$0.passato || $0.inizio > .now.addingTimeInterval(-6 * 3600) } : appelli
                let gruppi = settimane(lista)
                if let da = app.appelliDa, gruppi.first?.inizio != da {
                    Section(Formats.settimana(da)) {
                        Text("Nessun appello in questa settimana").foregroundStyle(.secondary)
                    }
                }
                if gruppi.isEmpty && app.appelliDa == nil {
                    Section { Text("Nessun appello in calendario").foregroundStyle(.secondary) }
                }
                ForEach(gruppi, id: \.inizio) { g in
                    Section(Formats.settimana(g.inizio)) {
                        ForEach(g.appelli) { AppelloRow(appello: $0) }
                    }
                }
            } else if app.appelli.error == nil {
                RigaSegnaposto()
            }
            UpdatedFooter(date: app.appelli.updatedAt).listRowBackground(Color.clear)
        }
        .refreshable { await app.loadAppelli() }
        .task { if app.appelli.updatedAt == nil { await app.loadAppelli() } }
        .sheet(isPresented: $showVaiA) {
            VaiADataSheet(iniziale: app.appelliDa ?? .now) { data in
                app.setAppelliDa(data)
                Task { await app.loadAppelli() }
            }
        }
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
                    TabellaSifaRows(tabella: tab, vuoto: "Nessuna prenotazione confermata")
                }
            }
            LiveSection(title: "Esiti da accettare", live: esiti, retry: loadEsiti) { TabellaSifaRows(tabella: $0, vuoto: "Nessun esito da accettare") }
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

/// Replica "Esami del tuo corso di studio" di SIFA: ricerca, Codice/Descrizione/Crediti e pulsante "Iscriviti",
/// che come sul sito apre "Selezione appello" con gli appelli disponibili per quell'esame.
struct IscrizioneAppelloSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var esami = Live<[EsameIscrivibile]>()
    @State private var descrizione = ""
    @State private var aperto: EsameIscrivibile?

    private func filtrati(_ list: [EsameIscrivibile]) -> [EsameIscrivibile] {
        let q = descrizione.trimmed
        return q.isEmpty ? list : list.filter { $0.descrizione.localizedCaseInsensitiveContains(q) || $0.codice.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                LiveSection(title: "Esami del tuo corso di studio", live: esami, retry: load) { list in
                    let rows = filtrati(list)
                    if rows.isEmpty { Text("Nessun esame trovato").foregroundStyle(.secondary) }
                    ForEach(rows) { e in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Testo.frase(e.descrizione)).font(.subheadline)
                                Text("\(e.codice.trimmed) · \(e.crediti) CFU")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Iscriviti") { aperto = e }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .searchable(text: $descrizione, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca insegnamento")
            .navigationTitle("Iscrizione agli appelli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .refreshable { await load() }
            .task { await esami.loadIfNeeded { try await app.services.sifa.esamiIscrivibili() } }
            .navigationDestination(item: $aperto) { AppelliDisponibiliView(esame: $0) }
        }
    }

    private func load() async { await esami.load { try await app.services.sifa.esamiIscrivibili() } }
}

/// "Selezione appello" di SIFA per un esame: appelli a cui ci si può iscrivere, con data e dettagli.
/// La conferma dell'iscrizione (scelta dell'appello e invio) resta sul sito ufficiale finché il passo successivo
/// non sarà osservato con appelli reali.
struct AppelliDisponibiliView: View {
    let esame: EsameIscrivibile
    @Environment(AppModel.self) private var app
    @State private var selezione = Live<SelezioneAppello>()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Testo.frase(esame.descrizione)).font(.headline)
                    Text("\(esame.codice) · \(esame.crediti) CFU").font(.caption).foregroundStyle(.secondary)
                }
            }
            LiveSection(title: "Appelli disponibili", live: selezione, retry: load) { s in
                if s.appelli.isEmpty {
                    Label(s.messaggio ?? "Nessun appello disponibile.", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(s.appelli) { a in
                        VStack(alignment: .leading, spacing: 3) {
                            if let d = a.data {
                                Text(Testo.maiuscolaIniziale(Formats.giornoEOra(d))).font(.subheadline.weight(.semibold))
                            }
                            Text(Testo.tipografia(a.titolo)).font(a.data == nil ? .subheadline.weight(.semibold) : .subheadline)
                            ForEach(a.dettagli, id: \.self) { Text(Testo.tipografia($0)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section {
                Link(destination: SifaApp.iscrizioneEsami.officialURL) {
                    Label("Completa l'iscrizione sul sito ufficiale", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("La lista è quella di SIFA › Esami del tuo corso di studio › Iscrizione. La conferma dell'iscrizione si fa ancora sul sito.")
            }
            UpdatedFooter(date: selezione.updatedAt)
        }
        .navigationTitle("Selezione appello")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await selezione.loadIfNeeded { try await app.services.sifa.appelliDisponibili(esame) } }
    }

    private func load() async { await selezione.load { try await app.services.sifa.appelliDisponibili(esame) } }
}

struct TabellaSifaRows: View {
    let tabella: TabellaSifa
    /// Messaggio quando la tabella è vuota (al posto del testo di SIFA, es. "Nessun esame presente").
    var vuoto: String? = nil
    var body: some View {
        if tabella.vuota {
            Text(vuoto ?? tabella.messaggio ?? "Nessun elemento").foregroundStyle(.secondary)
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
