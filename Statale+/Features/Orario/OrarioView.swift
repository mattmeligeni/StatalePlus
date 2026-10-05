import SwiftUI

/// Orario settimanale del corso scelto (default: quello dell'utente) nel periodo scelto con le pillole.
struct OrarioView: View {
    @Environment(AppModel.self) private var app
    @State private var weekOffset = 0
    @State private var showCorsi = false
    @State private var showInsegnamenti = false
    @State private var selected: Lezione?
    @State private var showVaiA = false
    @State private var evidenziata: String?
    @State private var evidenziaTask: Task<Void, Never>?
    @State private var scorriA: String?

    private var weekStart: Date {
        let cal = Formats.calendar
        let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: start) ?? start
    }

    private var days: [Date] {
        (0..<7).compactMap { Formats.calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                if let a = app.agenda {
                    Section {
                        PillPicker(items: a.corsoOrario.cdl.periodi, selected: app.periodoOrario, title: { Testo.maiuscolaIniziale($0.label.lowercased()) },
                                   titoloBreve: { Testo.periodoBreve($0.label) }) { p in
                            app.setPeriodoOrario(p.id)
                            weekOffset = 0
                            Task { await app.loadOrario(); jumpToFirstWeekIfNeeded() }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        weekHeader
                    } header: {
                        if !app.isMioCorsoOrario {
                            Text(Testo.nomeCorso(a.corsoOrario.cdl.label)).textCase(nil)
                        }
                    }
                }
                if app.orario.value == nil, app.orario.error == nil {
                    RigaSegnaposto()
                }
                if let error = app.orario.error {
                    ErrorRow(message: error) { await app.loadOrario() }
                }
                if let lezioni = app.orario.value {
                    let end = Formats.calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                    let week = lezioni.filter { $0.inizio >= weekStart && $0.inizio < end }
                    if week.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lezioni.isEmpty ? "Nessuna lezione per gli insegnamenti attivati" : "Nessuna lezione in questa settimana")
                                .foregroundStyle(.secondary)
                            if let next = lezioni.first(where: { $0.inizio >= end }) ?? lezioni.last(where: { $0.inizio < weekStart }) {
                                Button("Vai alla settimana del \(next.inizio.formatted(.dateTime.day().month(.wide).locale(Formats.it)))") {
                                    weekOffset = weeks(to: next.inizio)
                                }
                                .font(.callout)
                            }
                        }
                    }
                    ForEach(days, id: \.self) { day in
                        let items = week.filter { Formats.calendar.isDate($0.inizio, inSameDayAs: day) }
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { l in
                                    Button { selected = l } label: { LezioneRow(lezione: l) }
                                        .tint(.primary)
                                        .listRowBackground(evidenziata == chiave(l)
                                                           ? Color.accentColor.opacity(0.22) : Color(.secondarySystemGroupedBackground))
                                        .id(chiave(l))
                                }
                            } header: {
                                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Formats.it)))
                                    .foregroundStyle(Formats.calendar.isDateInToday(day) ? Color.accentColor : .secondary)
                            }
                        }
                    }
                }
                UpdatedFooter(date: app.orario.updatedAt).listRowBackground(Color.clear)
            }
            .onChange(of: scorriA) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                scorriA = nil
            }
            }
            .navigationTitle(app.isMioCorsoOrario ? "Orario" : (app.agenda?.corsoOrario.cdl.codiceLettera ?? "Orario"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showInsegnamenti = true } label: { Label("Insegnamenti…", systemImage: "checklist") }
                        Button { showCorsi = true } label: { Label("Cambia corso…", systemImage: "building.columns") }
                        if !app.isMioCorsoOrario, let mio = app.agenda?.mioCorsoOrario {
                            Button { cambiaCorso(mio) } label: { Label("Torna al mio corso", systemImage: "person.crop.circle") }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable { app.segnaRefresh(); await app.loadOrario(refreshInsegnamenti: true) }
            .task { if app.orario.updatedAt == nil { await app.loadOrario() } }
            .onAppear { consumaRichiesta() }
            .onChange(of: app.orarioRichiesta?.id) { consumaRichiesta() }
            .sheet(isPresented: $showInsegnamenti) { InsegnamentiSheet() }
            .sheet(isPresented: $showCorsi) {
                CorsoPicker(titolo: "Corso per l'orario", albero: app.alberoOrario, load: app.loadAlberoOrario,
                            attuale: app.agenda?.corsoOrario, mio: app.agenda?.mioCorsoOrario) { cambiaCorso($0) }
            }
            .sheet(item: $selected) { LezioneDetail(lezione: $0).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showVaiA) {
                VaiADataSheet(iniziale: weekStart) { data in
                    if vaiA(data) { Task { await app.loadOrario() } }
                }
            }
        }
    }

    /// Porta alla settimana della data; se la data cade in un altro periodo didattico, cambia anche periodo.
    /// Porta alla settimana della data; se la data cade in un altro periodo didattico cambia periodo
    /// e restituisce true (l'orario va ricaricato).
    @discardableResult
    private func vaiA(_ data: Date) -> Bool {
        weekOffset = weeks(to: data)
        guard let periodi = app.agenda?.corsoOrario.cdl.periodi,
              let p = AgendaConfig.periodoAttuale(periodi, now: data), p != app.periodoOrario else { return false }
        app.setPeriodoOrario(p.id)
        return true
    }

    /// Lezione richiesta da Oggi: consumata subito, poi mostrata in un task indipendente
    /// (così azzerare la richiesta non annulla l'evidenziazione).
    private func consumaRichiesta() {
        guard let l = app.orarioRichiesta else { return }
        app.orarioRichiesta = nil
        evidenziaTask?.cancel()
        evidenziaTask = Task { await mostra(l) }
    }

    /// Settimana e periodo giusti, scorrimento fino alla lezione ed evidenziazione per qualche secondo.
    private func mostra(_ l: Lezione) async {
        evidenziata = nil
        if vaiA(l.inizio) || app.orario.value == nil { await app.loadOrario() }
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(150))   // lascia comparire le righe della settimana
        scorriA = chiave(l)
        withAnimation(.easeOut(duration: 0.3)) { evidenziata = chiave(l) }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.8)) { evidenziata = nil }
    }

    /// Stessa lezione anche se ricaricata (gli id XML sono stabili, ma si confrontano anche orario e insegnamento).
    private func chiave(_ l: Lezione) -> String { "\(l.codiceInsegnamento)|\(l.inizio.timeIntervalSince1970)" }

    private func cambiaCorso(_ c: CorsoSelezionato) {
        app.setCorsoOrario(c)
        weekOffset = 0
        Task { await app.loadOrario(); jumpToFirstWeekIfNeeded() }
    }

    /// Se la settimana corrente è vuota ma il periodo ha lezioni future, salta alla prima.
    private func jumpToFirstWeekIfNeeded() {
        guard let lezioni = app.orario.value, !lezioni.isEmpty else { return }
        let end = Formats.calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        guard !lezioni.contains(where: { $0.inizio >= weekStart && $0.inizio < end }),
              let first = lezioni.first(where: { $0.inizio >= weekStart }) else { return }
        weekOffset = weeks(to: first.inizio)
    }

    private func weeks(to date: Date) -> Int {
        let cal = Formats.calendar
        let a = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let b = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return cal.dateComponents([.weekOfYear], from: a, to: b).weekOfYear ?? 0
    }

    private var weekHeader: some View {
        HStack {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 4) {
                Text(weekTitle).font(.headline)
                HStack(spacing: 14) {
                    Button { showVaiA = true } label: { Label("Vai a data", systemImage: "calendar.badge.clock") }
                    if weekOffset != 0 { Button("Torna a oggi") { weekOffset = 0 } }
                }
                .font(.caption)
            }
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.borderless)
    }

    private var weekTitle: String {
        let end = Formats.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let f = Date.FormatStyle().day().month(.abbreviated).locale(Formats.it)
        return "\(weekStart.formatted(f)) – \(end.formatted(f))"
    }
}

struct LezioneDetail: View {
    /// La lezione aperta; i dati mostrati sono quelli attuali (con le modifiche locali) cercati per id.
    let lezione: Lezione
    @Environment(AppModel.self) private var app
    @State private var nomeEspanso = false
    @State private var modifica = false
    @State private var confermaRipristino = false

    private var attuale: Lezione { app.lezione(lezione.id) ?? lezione.conModifica(app.modificheLezioni[lezione.id]) }

    /// Il nome completo sta nella sezione in alto: tap per espanderlo se è lungo.
    private var nomeLungo: Bool { lezione.insegnamento.count > 70 }

    private var annullataDaTe: Binding<Bool> {
        Binding(get: { attuale.annullato }, set: { valore in
            var m = app.modificheLezioni[lezione.id] ?? ModificaLezione()
            // Se coincide con l'Agenda la modifica non serve.
            m.annullata = valore == (attuale.ufficiale?.annullato ?? lezione.annullato) ? nil : valore
            m.salvata = .now
            app.salvaModifica(m, lezione: lezione.id)
        })
    }

    var body: some View {
        let l = attuale
        NavigationStack {
            List {
                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { nomeEspanso.toggle() }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(l.insegnamento)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nomeEspanso || !nomeLungo ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if nomeLungo {
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(nomeEspanso ? 180 : 0))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!nomeLungo)
                    .accessibilityHint(nomeLungo ? (nomeEspanso ? "Comprimi il nome" : "Mostra il nome completo") : "")
                }
                if let u = l.ufficiale {
                    Section {
                        Label("Modificata da te", systemImage: "pencil").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                        if u.aula != l.aula || u.sede != l.sede { LabeledContent("Agenda: luogo", value: "\(u.aula) · \(u.sede)") }
                        if u.docente != l.docente { LabeledContent("Agenda: docente", value: Testo.persona(u.docente)) }
                        if u.annullato != l.annullato { LabeledContent("Agenda: stato", value: u.annullato ? "Annullata" : "Confermata") }
                        Button("Ripristina i dati dell'Agenda", role: .destructive) { confermaRipristino = true }
                    } footer: {
                        Text("Le modifiche restano solo su questo dispositivo e non possono essere verificate: in caso di dubbio fanno fede i canali ufficiali del corso.")
                    }
                }
                Section {
                    LabeledContent("Quando") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(l.inizio.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Formats.it)))
                            Text("\(Formats.time(l.inizio)) – \(Formats.time(l.fine))").monospacedDigit()
                        }
                    }
                    LabeledContent("Aula", value: l.aula)
                    LabeledContent("Sede", value: l.sede)
                    LabeledContent("Docente", value: Testo.persona(l.docente))
                    LabeledContent("Tipo", value: l.tipo)
                    TimeStatusBadge(inizio: l.inizio, fine: l.fine, annullato: l.annullato)
                    if !l.note.isEmpty { Text(l.note) }
                }
                MapsButton(aula: l.aula, sede: l.sede, codici: [l.aulaCodice]) {
                    Label("Apri in Mappe", systemImage: "map")
                }
                Section {
                    Toggle(isOn: annullataDaTe) {
                        Label("Lezione annullata", systemImage: "calendar.badge.minus")
                    }
                    .tint(.red)
                    Button { modifica = true } label: {
                        Label("Modifica aula, sede o docente", systemImage: "pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Per i corsi in cui il docente non aggiorna l'Agenda web: le modifiche valgono solo su questo dispositivo, in Oggi e in Orario, e non possono essere verificate.")
                }
            }
            .listSectionSpacing(.compact)
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle("Lezione")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $modifica) { ModificaLezioneSheet(lezione: l) }
            .confirmationDialog("Ripristinare i dati dell'Agenda?", isPresented: $confermaRipristino, titleVisibility: .visible) {
                Button("Ripristina", role: .destructive) { app.salvaModifica(nil, lezione: lezione.id) }
            } message: {
                Text("La modifica fatta su questo dispositivo verrà eliminata.")
            }
        }
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

/// Modifica locale di aula, sede e docente di una lezione; l'aula si può scegliere dall'elenco EasyRoom (così Mappe
/// porta alla sede giusta) o scrivere a mano.
private struct ModificaLezioneSheet: View {
    let lezione: Lezione
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var aula = ""
    @State private var aulaScelta: Aula?
    @State private var sede = ""
    @State private var docente = ""
    @State private var annullata = false
    @FocusState private var campoAttivo: Campo?

    private enum Campo { case aula, sede, docente }

    private var ufficiale: ValoriUfficialiLezione {
        lezione.ufficiale ?? ValoriUfficialiLezione(aula: lezione.aula, aulaCodice: lezione.aulaCodice, sede: lezione.sede,
                                                     docente: lezione.docente, annullato: lezione.annullato)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SceltaAula { a in aula = a.nome; sede = a.sede; aulaScelta = a }
                    } label: {
                        Label("Scegli dall'elenco delle aule", systemImage: "building.2")
                    }
                    TextField("Aula", text: $aula)
                        .autocorrectionDisabled()
                        .focused($campoAttivo, equals: .aula)
                        .submitLabel(.next)
                        .onSubmit { campoAttivo = .sede }
                    TextField("Sede", text: $sede)
                        .autocorrectionDisabled()
                        .focused($campoAttivo, equals: .sede)
                        .submitLabel(.next)
                        .onSubmit { campoAttivo = .docente }
                } header: {
                    Text("Luogo")
                } footer: {
                    Text("Scegliendo dall'elenco, \"Apri in Mappe\" porta all'indirizzo dell'aula.")
                }
                Section("Docente") {
                    TextField("Docente", text: $docente)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .focused($campoAttivo, equals: .docente)
                        .submitLabel(.done)
                }
                Section {
                    Toggle("Lezione annullata", isOn: $annullata).tint(.red)
                }
                Section {
                } footer: {
                    Text("Agenda: \(ufficiale.aula) · \(ufficiale.sede) · \(Testo.persona(ufficiale.docente))\(ufficiale.annullato ? " · annullata" : "")")
                }
            }
            .tastieraConChiudi()
            .navigationTitle("Modifica lezione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { salva(); dismiss() }.bold() }
            }
            .onAppear {
                aula = lezione.aula; sede = lezione.sede; docente = Testo.persona(lezione.docente); annullata = lezione.annullato
            }
        }
    }

    private func salva() {
        let u = ufficiale
        var m = ModificaLezione()
        let a = aula.trimmed, s = sede.trimmed, d = docente.trimmed
        // Il codice EasyRoom vale solo se l'aula è ancora quella scelta dall'elenco.
        if !a.isEmpty, a != u.aula { m.aula = a; m.aulaCodice = aulaScelta?.nome == a ? aulaScelta?.codice : "" }
        if !s.isEmpty, s != u.sede { m.sede = s }
        if !d.isEmpty, d != Testo.persona(u.docente), d != u.docente { m.docente = d }
        if annullata != u.annullato { m.annullata = annullata }
        app.salvaModifica(m, lezione: lezione.id)
    }
}

/// Elenco aule di EasyRoom per sede, con ricerca.
private struct SceltaAula: View {
    let scegli: (Aula) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            LiveSection(title: "Aule", live: app.aule, retry: { await app.loadAule(force: true) }) { occ in
                let q = query.trimmed
                ForEach(occ.sedi.filter { !$0.aule.isEmpty }) { sede in
                    let aule = sede.aule.filter { q.isEmpty || $0.nome.localizedCaseInsensitiveContains(q) || sede.nome.localizedCaseInsensitiveContains(q) }
                    if !aule.isEmpty {
                        Section(sede.nome) {
                            ForEach(aule) { a in
                                Button {
                                    scegli(a)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.nome).foregroundStyle(.primary)
                                        if let c = a.capienza { Text("\(c) posti").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Aula o sede")
        .autocorrectionDisabled()
        .navigationTitle("Scegli l'aula")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.loadAule() }
    }
}

/// Attivazione degli insegnamenti del corso e del periodo mostrati.
struct InsegnamentiSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var scelti: Set<String> = []

    private var lista: [InsegnamentoAgenda] { app.insegnamentiOrario.value ?? [] }

    var body: some View {
        NavigationStack {
            List {
                if lista.isEmpty {
                    if app.orario.isLoading { ProgressView() } else { Text("Nessun insegnamento per questo periodo").foregroundStyle(.secondary) }
                }
                let anni = Array(Set(lista.map(\.anno))).sorted()
                if anni.count > 1 {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(anni, id: \.self) { anno in
                                    Button("Solo \(anno)° anno") { scelti = Set(lista.filter { $0.anno == anno }.map(\.codice)) }
                                        .buttonStyle(.bordered)
                                }
                                Button("Tutti") { scelti = Set(lista.map(\.codice)) }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
                ForEach(anni, id: \.self) { anno in
                    Section("\(anno)° anno") {
                        ForEach(lista.filter { $0.anno == anno }) { ins in
                            Toggle(isOn: Binding(
                                get: { scelti.contains(ins.codice) },
                                set: { on in if on { scelti.insert(ins.codice) } else { scelti.remove(ins.codice) } })) {
                                VStack(alignment: .leading) {
                                    Text(ins.nome).font(.subheadline)
                                    Text("\(ins.codice) · \(ins.crediti) CFU · \(Testo.persona(ins.docente))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(app.periodoOrario.map { Testo.maiuscolaIniziale($0.label.lowercased()) } ?? "Insegnamenti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        if let cdl = app.agenda?.corsoOrario.cdl {
                            // Mantiene le scelte degli altri periodi dello stesso corso.
                            let altri = (app.agenda?.attivati[cdl.valore] ?? []).subtracting(lista.map(\.codice))
                            app.setAttivati(cdl: cdl.valore, altri.union(scelti))
                        }
                        dismiss()
                        Task { await app.loadOrario() }
                    }
                }
            }
            .onAppear {
                if let cdl = app.agenda?.corsoOrario.cdl { scelti = app.attivati(cdl: cdl, insegnamenti: lista) }
            }
        }
    }
}

/// Scelta di un corso di laurea: scuola → tipo → corso (alberi Agenda orario o esami).
struct CorsoPicker: View {
    let titolo: String
    let albero: Live<[AgendaScuola]>
    let load: () async -> Void
    let attuale: CorsoSelezionato?
    let mio: CorsoSelezionato?
    let onSelect: (CorsoSelezionato) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let mio {
                    Section("Il mio corso") { corsoButton(mio) }
                }
                LiveSection(title: "Scuole", live: albero, retry: load) { scuole in
                    ForEach(scuole.filter { !$0.lauree.isEmpty }, id: \.label) { scuola in
                        NavigationLink(scuola.label == "--" ? "Altro" : scuola.label) { tipi(scuola) }
                    }
                }
            }
            .navigationTitle(titolo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .task { await load() }
        }
    }

    private func tipi(_ scuola: AgendaScuola) -> some View {
        List(scuola.lauree, id: \.tipo) { laurea in
            NavigationLink(laurea.tipo.capitalized) { corsi(scuola, laurea) }
        }
        .navigationTitle(scuola.label)
    }

    private func corsi(_ scuola: AgendaScuola, _ laurea: AgendaLaurea) -> some View {
        CorsiList(scuola: scuola, laurea: laurea, row: corsoButton)
    }

    private func corsoButton(_ c: CorsoSelezionato) -> some View {
        Button {
            onSelect(c)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(Testo.nomeCorso(c.cdl.label)).foregroundStyle(.primary)
                    Text(c.cdl.codiceLettera).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if c.cdl.valore == attuale?.cdl.valore { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
    }
}

private struct CorsiList<Row: View>: View {
    let scuola: AgendaScuola
    let laurea: AgendaLaurea
    let row: (CorsoSelezionato) -> Row
    @State private var query = ""

    var body: some View {
        List(laurea.cdl.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) || $0.codiceLettera.localizedCaseInsensitiveContains(query) },
             id: \.valore) { cdl in
            row(CorsoSelezionato(scuola: scuola.label, tipo: laurea.tipo, cdl: cdl))
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca corso")
        .autocorrectionDisabled()
        .navigationTitle(laurea.tipo.capitalized)
    }
}
