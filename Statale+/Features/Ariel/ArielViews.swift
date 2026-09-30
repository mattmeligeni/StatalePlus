import SwiftUI
import QuickLook

/// Lista corsi dell'offerta dell'a.a. corrente: attivi in cima, gli altri grigiati.
struct ArielCoursesView: View {
    @Environment(AppModel.self) private var app
    @State private var offerta = Live<[InsegnamentoOfferta]>()
    @State private var mostraSenzaSito = false

    var body: some View {
        NavigationStack {
            List {
                if let e = app.arielError, offerta.value == nil {
                    Section { ErrorRow(message: e, retry: reload) }
                }
                Section {
                    NavigationLink { ScadenzeArielView() } label: {
                        HStack {
                            RigaIcona("Scadenze ed eventi", simbolo: "calendar.badge.clock")
                            Spacer()
                            if let n = app.scadenzeAriel.value?.count, n > 0 { Text("\(n)").foregroundStyle(.secondary) }
                        }
                    }
                    NavigationLink { NotificheArielView() } label: {
                        HStack {
                            RigaIcona("Notifiche", simbolo: "bell")
                            Spacer()
                            if let n = app.notificheAriel.value?.nonLette, n > 0 {
                                Text("\(n)").font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 2).background(.red, in: Capsule())
                            }
                        }
                    }
                }
                LiveSection(title: "Con sito attivo · \(Formats.currentAcademicYear())", live: offerta, retry: reload) { corsi in
                    let attivi = corsi.filter(\.attivo).sorted { $0.titolo < $1.titolo }
                    if attivi.isEmpty { Text("Nessun corso con sito attivo").foregroundStyle(.secondary) }
                    ForEach(attivi) { corso in
                        NavigationLink { CourseDetailView(corso: corso) } label: { CourseRow(corso: corso) }
                    }
                }
                if let corsi = offerta.value, corsi.contains(where: { !$0.attivo }) {
                    let altri = corsi.filter { !$0.attivo }.sorted { $0.titolo < $1.titolo }
                    Section {
                        DisclosureGroup(isExpanded: $mostraSenzaSito) {
                            ForEach(altri) { CourseRow(corso: $0).foregroundStyle(.secondary) }
                        } label: {
                            Text("Senza sito didattico (\(altri.count))").font(.subheadline)
                        }
                    }
                }
                UpdatedFooter(date: offerta.updatedAt ?? app.store.snapshot.offertaAggiornata).listRowBackground(Color.clear)
            }
            .navigationTitle("Ariel")
            .refreshable {
                async let a: Void = reload()
                async let b: Void = app.loadScadenzeAriel(force: true)
                async let c: Void = app.loadNotificheAriel()
                _ = await (a, b, c)
            }
            .task {
                async let b: Void = app.loadScadenzeAriel(force: false)
                async let c: Void = app.notificheAriel.updatedAt == nil ? app.loadNotificheAriel() : ()
                _ = await (b, c)
            }
            .task {
                if offerta.value == nil, let cached = app.store.snapshot.offerta,
                   !app.store.isStale(app.store.snapshot.offertaAggiornata, ttl: StableStore.ttlOfferta) {
                    await offerta.load { cached }
                } else {
                    await offerta.loadIfNeeded(fetch)
                }
            }
        }
    }

    private func reload() async { await offerta.load(fetch) }

    private func fetch() async throws -> [InsegnamentoOfferta] {
        let list = try await app.services.ariel.offerta()
        app.store.update { $0.offerta = list; $0.offertaAggiornata = .now }
        return list
    }
}

private struct CourseRow: View {
    let corso: InsegnamentoOfferta
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(corso.titolo).font(.subheadline.weight(corso.attivo ? .semibold : .regular)).lineLimit(3)
            Text(([corso.codice] + (corso.titolari.isEmpty ? [] : [corso.titolari.map { Testo.persona($0) }.joined(separator: ", ")]))
                .joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Dettaglio corso

struct CourseDetailView: View {
    let corso: InsegnamentoOfferta
    @Environment(AppModel.self) private var app
    @State private var struttura = Live<CourseState>()
    @State private var scheda = Live<SchedaInsegnamento?>()

    private var courseId: String { corso.courseId ?? "" }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(corso.titolo).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(([corso.codice] + corso.titolari.map { Testo.persona($0) }).joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            }
            LiveSection(title: "Scheda insegnamento", live: scheda, retry: { await loadScheda(force: true) }) { s in
                if let s { SchedaView(scheda: s, corso: corso) } else { Text("Scheda non disponibile").foregroundStyle(.secondary) }
            }
            if let state = struttura.value {
                // Una sezione della lista per ogni sezione Moodle.
                ForEach(state.section.filter(\.visible)) { section in
                    let mods = state.modules(in: section).filter { $0.uservisible ?? $0.visible }
                    if !mods.isEmpty {
                        Section(section.title) {
                            ForEach(mods) { m in
                                NavigationLink { ModuleView(module: m) } label: { RigaIcona(m.name, simbolo: icon(for: m.module)) }
                            }
                        }
                    }
                }
                if let e = struttura.error { Section { ErrorRow(message: e, retry: loadStruttura) } }
            } else {
                LiveSection(title: "Contenuti", live: struttura, retry: loadStruttura) { _ in EmptyView() }
            }
            if !courseId.isEmpty { MaterialiCorsoSection(courseId: courseId, titolo: corso.titolo) }
            Section("Corso") {
                NavigationLink { ValutazioniView(courseId: courseId) } label: { RigaIcona("Valutazioni", simbolo: "checkmark.seal") }
                NavigationLink { PartecipantiView(courseId: courseId) } label: { RigaIcona("Partecipanti", simbolo: "person.2") }
            }
            UpdatedFooter(date: struttura.updatedAt).listRowBackground(Color.clear)
        }
        .navigationTitle(corso.codice)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            async let a: Void = loadStruttura()
            async let b: Void = loadScheda(force: true)
            _ = await (a, b)
        }
        .task {
            async let a: Void = struttura.loadIfNeeded { try await app.services.ariel.struttura(courseId: courseId) }
            async let b: Void = loadScheda(force: false)
            _ = await (a, b)
        }
    }

    private func loadStruttura() async {
        await struttura.load { try await app.services.ariel.struttura(courseId: courseId) }
    }

    /// Scheda = info generale → cache persistita con TTL.
    private func loadScheda(force: Bool) async {
        // Le schede in cache senza titolari (salvate prima che li leggessimo) si riscaricano.
        if !force, let c = app.store.snapshot.schede[courseId], c.scheda.titolari != nil,
           !app.store.isStale(c.aggiornata, ttl: StableStore.ttlScheda) {
            await scheda.load { c.scheda }
            return
        }
        await scheda.load {
            let s = try await app.services.ariel.scheda(courseId: courseId)
            if let s { app.store.update { $0.schede[courseId] = SchedaCache(scheda: s, aggiornata: .now) } }
            return s
        }
    }

    private func icon(for module: String) -> String {
        switch module {
        case "forum": "bubble.left.and.bubble.right"
        case "folder": "folder"
        case "resource": "doc"
        case "url": "link"
        case "assign": "tray.and.arrow.up"
        case "quiz": "questionmark.circle"
        default: "square.stack"
        }
    }
}

private struct SchedaView: View {
    let scheda: SchedaInsegnamento
    let corso: InsegnamentoOfferta
    @State private var espanso = false
    @State private var showCalendario = false
    @State private var docente: TitolareSito?

    private var titolari: [TitolareSito] { scheda.titolari ?? [] }

    /// Titolari del sito che non compaiono fra i docenti delle edizioni (es. coordinatore del corso).
    private var altriTitolari: [TitolareSito] {
        titolari.filter { t in !scheda.docenti.contains { t.corrisponde(a: $0) } }
    }

    var body: some View {
        if let o = scheda.obiettivi {
            VStack(alignment: .leading) {
                Text(o).font(.callout).lineLimit(espanso ? nil : 4)
                Button(espanso ? "Mostra meno" : "Mostra tutto") { espanso.toggle() }.font(.caption).buttonStyle(.borderless)
            }
        }
        if let p = scheda.periodo { LabeledContent("Periodo", value: p) }
        if let l = scheda.lingua { LabeledContent("Lingua", value: l) }
        ForEach(scheda.docenti, id: \.self) { d in
            if let t = titolari.first(where: { $0.corrisponde(a: d) }) {
                rigaDocente("Docente", valore: d, titolare: t)
            } else {
                LabeledContent("Docente", value: d)
            }
        }
        ForEach(altriTitolari) { rigaDocente("Titolare del sito", valore: $0.nome, titolare: $0) }
        // Senza titolari (scheda vecchia o blocco diverso): email e CV restano qui.
        if titolari.isEmpty {
            if let e = scheda.emailDocente, let url = URL(string: "mailto:\(e)") { Link(destination: url) { Label(e, systemImage: "envelope") } }
            if let u = scheda.cvDocenteURL { DocumentoPDFRow(titolo: "CV docente", simbolo: "person.text.rectangle", url: u) }
        }
        Button { showCalendario = true } label: { Label("Calendario lezioni", systemImage: "calendar") }
            .sheet(isPresented: $showCalendario) { calendario }
            .sheet(item: $docente) { DocenteSheet(titolare: $0).presentationDetents([.medium, .large]) }
    }

    private func rigaDocente(_ etichetta: String, valore: String, titolare: TitolareSito) -> some View {
        Button { docente = titolare } label: {
            LabeledContent(etichetta) {
                HStack(spacing: 4) {
                    Text(valore).foregroundStyle(Color.accentColor)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .tint(.primary)
        .accessibilityHint("Mostra contatti e ricevimento")
    }

    private var calendario: some View {
        LezioniInsegnamentoSheet(titolo: corso.titolo,
                                 codiceAgenda: scheda.codiceAgenda ?? "\(corso.codice)_1",
                                 anno: scheda.annoAgenda ?? String(Formats.currentAcademicYear().prefix(4)))
    }
}

/// Riepilogo del docente dalla scheda insegnamento: ruolo, contatti, sede e ricevimento.
private struct DocenteSheet: View {
    let titolare: TitolareSito
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titolare.nome).font(.title3.bold())
                        if let r = titolare.ruolo { Text(r).foregroundStyle(.secondary) }
                    }
                }
                if titolare.ricevimento != nil || titolare.luogoRicevimento != nil {
                    Section("Ricevimento") {
                        if let r = titolare.ricevimento {
                            Label { Text(r) } icon: { Image(systemName: "clock") }
                        }
                        if let l = titolare.luogoRicevimento {
                            Label { Text(l) } icon: { Image(systemName: "door.left.hand.open") }
                        }
                    }
                }
                Section("Contatti") {
                    if let e = titolare.email, let url = URL(string: "mailto:\(e)") {
                        Link(destination: url) { Label(e, systemImage: "envelope") }
                    }
                    if let t = titolare.telefono, let url = URL(string: "tel:\(t.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) { Label(t, systemImage: "phone") }
                    }
                    if let s = titolare.struttura { Label(s, systemImage: "building.columns") }
                    if let i = titolare.indirizzo {
                        Button { if let u = Maps.url(address: i) { openURL(u) } } label: {
                            Label(i, systemImage: "map")
                        }
                    }
                    if let s = titolare.sede, s.matchKey != titolare.indirizzo?.matchKey {
                        Label(s, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
                    }
                }
                if let u = titolare.cvURL {
                    Section { DocumentoPDFRow(titolo: "Curriculum", simbolo: "doc.text", url: u) }
                }
            }
            .listSectionSpacing(.compact)
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle("Docente")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

// MARK: - Modulo

struct ModuleView: View {
    let module: CourseState.Module
    @Environment(AppModel.self) private var app
    @State private var dettaglio = Live<ModuloDettaglio>()
    @State private var preview: URL?
    @State private var downloading: URL?
    @State private var downloadError: String?

    var body: some View {
        List {
            LiveSection(title: module.modname, live: dettaglio, retry: load) { d in
                if !d.descrizione.isEmpty {
                    Text(Testo.markdown(d.descrizione)).font(.callout).textSelection(.enabled)
                } else if d.file.isEmpty && d.discussioni.isEmpty {
                    Text("Nessun contenuto testuale").foregroundStyle(.secondary)
                }
                ForEach(d.file) { f in
                    Button { Task { await open(f) } } label: {
                        HStack {
                            Label(f.nome, systemImage: "doc")
                            Spacer()
                            if downloading == f.url { ProgressView() }
                        }
                    }
                }
                ForEach(d.discussioni) { disc in
                    NavigationLink { DiscussionView(discussione: disc) } label: {
                        VStack(alignment: .leading) {
                            Text(disc.titolo).font(.subheadline.weight(.semibold))
                            HStack {
                                Text(disc.autore)
                                if let d = disc.ultimaAttivita ?? disc.creata { Text("· " + d.italiano(date: .abbreviated, time: .shortened)) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let downloadError { Section { Text(downloadError).foregroundStyle(.red) } }
        }
        .navigationTitle(module.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await dettaglio.loadIfNeeded { try await app.services.ariel.modulo(module) } }
        .quickLookPreview($preview)
    }

    private func load() async { await dettaglio.load { try await app.services.ariel.modulo(module) } }

    private func open(_ f: FileMoodle) async {
        downloading = f.url
        defer { downloading = nil }
        do { preview = try await app.services.ariel.scarica(f); downloadError = nil }
        catch { downloadError = app.message(error) }
    }
}

struct DiscussionView: View {
    let discussione: DiscussioneForum
    @Environment(AppModel.self) private var app
    @State private var posts = Live<[PostForum]>()

    var body: some View {
        List {
            LiveSection(title: "Messaggi", live: posts, retry: load) { list in
                ForEach(list) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.oggetto).font(.headline)
                        HStack {
                            Text(p.autore)
                            if let d = p.data { Text("· " + d.italiano(date: .abbreviated, time: .shortened)) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Text(Testo.markdown(p.testo)).font(.callout).textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(discussione.titolo)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await posts.loadIfNeeded { try await app.services.ariel.discussione(discussione) } }
        .onAppear { app.segnaAvvisoLetto(discussione) }
    }

    private func load() async { await posts.load { try await app.services.ariel.discussione(discussione) } }
}

struct PartecipantiView: View {
    let courseId: String
    @Environment(AppModel.self) private var app
    @State private var list = Live<[Partecipante]>()

    var body: some View {
        List {
            LiveSection(title: "Partecipanti", live: list, retry: load) { people in
                ForEach(people) { p in
                    VStack(alignment: .leading) {
                        Text(p.nome)
                        Text([p.ruoli, p.gruppi].filter { !$0.isEmpty && $0 != "Nessun gruppo" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Partecipanti")
        .refreshable { await load() }
        .task { await list.loadIfNeeded { try await app.services.ariel.partecipanti(courseId: courseId) } }
    }

    private func load() async { await list.load { try await app.services.ariel.partecipanti(courseId: courseId) } }
}

struct ValutazioniView: View {
    let courseId: String
    @Environment(AppModel.self) private var app
    @State private var voci = Live<[VoceValutazione]>()

    var body: some View {
        List {
            LiveSection(title: "Valutazioni", live: voci, retry: load) { list in
                if list.isEmpty { Text("Nessuna valutazione").foregroundStyle(.secondary) }
                ForEach(list) { v in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.elemento).font(.subheadline.weight(.semibold))
                        HStack(spacing: 16) {
                            LabeledContent("Voto", value: v.valutazione)
                            LabeledContent("Intervallo", value: v.intervallo)
                            LabeledContent("%", value: v.percentuale)
                        }
                        .font(.caption)
                        if !v.feedback.isEmpty { Text(v.feedback).font(.caption) }
                    }
                }
            }
        }
        .navigationTitle("Valutazioni")
        .refreshable { await load() }
        .task { await voci.loadIfNeeded { try await app.services.ariel.valutazioni(courseId: courseId) } }
    }

    private func load() async { await voci.load { try await app.services.ariel.valutazioni(courseId: courseId) } }
}
