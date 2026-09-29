import SwiftUI
import QuickLook

/// Lista corsi dell'offerta dell'a.a. corrente: attivi in cima, gli altri grigiati.
struct ArielCoursesView: View {
    @Environment(AppModel.self) private var app
    @State private var offerta = Live<[InsegnamentoOfferta]>()

    var body: some View {
        NavigationStack {
            List {
                if let e = app.arielError, offerta.value == nil {
                    Section { ErrorRow(message: e, retry: reload) }
                }
                LiveSection(title: "Anno accademico \(Formats.currentAcademicYear())", live: offerta, retry: reload) { corsi in
                    ForEach(corsi.sorted { ($0.attivo ? 0 : 1, $0.titolo) < ($1.attivo ? 0 : 1, $1.titolo) }) { corso in
                        if corso.attivo {
                            NavigationLink { CourseDetailView(corso: corso) } label: { CourseRow(corso: corso) }
                        } else {
                            CourseRow(corso: corso).foregroundStyle(.secondary)
                        }
                    }
                }
                UpdatedFooter(date: offerta.updatedAt ?? app.store.snapshot.offertaAggiornata).listRowBackground(Color.clear)
            }
            .navigationTitle("Ariel")
            .refreshable { await reload() }
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
            HStack {
                Text(corso.codice).font(.caption.monospaced())
                if !corso.titolari.isEmpty { Text("· " + corso.titolari.map(\.capitalized).joined(separator: ", ")).font(.caption) }
            }
            .foregroundStyle(.secondary)
            if !corso.attivo { Text("Nessun sito didattico attivato").font(.caption2).italic() }
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
            LiveSection(title: "Scheda insegnamento", live: scheda, retry: { await loadScheda(force: true) }) { s in
                if let s { SchedaView(scheda: s, corso: corso) } else { Text("Scheda non disponibile").foregroundStyle(.secondary) }
            }
            LiveSection(title: "Contenuti", live: struttura, retry: loadStruttura) { state in
                ForEach(state.section.filter(\.visible)) { section in
                    let mods = state.modules(in: section).filter { $0.uservisible ?? $0.visible }
                    if !mods.isEmpty {
                        Text(section.title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(mods) { m in
                            NavigationLink { ModuleView(module: m) } label: {
                                Label(m.name, systemImage: icon(for: m.module))
                            }
                        }
                    }
                }
            }
            Section("Corso") {
                NavigationLink { ValutazioniView(courseId: courseId) } label: { Label("Valutazioni", systemImage: "checkmark.seal") }
                NavigationLink { PartecipantiView(courseId: courseId) } label: { Label("Partecipanti", systemImage: "person.3") }
            }
            UpdatedFooter(date: struttura.updatedAt).listRowBackground(Color.clear)
        }
        .navigationTitle(corso.codice)
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
        if !force, let c = app.store.snapshot.schede[courseId], !app.store.isStale(c.aggiornata, ttl: StableStore.ttlScheda) {
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

    var body: some View {
        if let o = scheda.obiettivi {
            VStack(alignment: .leading) {
                Text(o).font(.callout).lineLimit(espanso ? nil : 4)
                Button(espanso ? "Mostra meno" : "Mostra tutto") { espanso.toggle() }.font(.caption).buttonStyle(.borderless)
            }
        }
        if let p = scheda.periodo { LabeledContent("Periodo", value: p) }
        if let l = scheda.lingua { LabeledContent("Lingua", value: l) }
        ForEach(scheda.docenti, id: \.self) { LabeledContent("Docente", value: $0) }
        if let e = scheda.emailDocente, let url = URL(string: "mailto:\(e)") { Link(destination: url) { Label(e, systemImage: "envelope") } }
        if let u = scheda.programmaURL { Link(destination: u) { Label("Programma e organizzazione didattica", systemImage: "doc.text") } }
        Button { showCalendario = true } label: { Label("Calendario lezioni", systemImage: "calendar") }
            .sheet(isPresented: $showCalendario) { calendario }
        if let u = scheda.cvDocenteURL { Link(destination: u) { Label("CV docente", systemImage: "person.text.rectangle") } }
    }

    private var calendario: some View {
        LezioniInsegnamentoSheet(titolo: corso.titolo,
                                 codiceAgenda: scheda.codiceAgenda ?? "\(corso.codice)_1",
                                 anno: scheda.annoAgenda ?? String(Formats.currentAcademicYear().prefix(4)))
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
                    Text(d.descrizione).font(.callout).textSelection(.enabled)
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
                                if let d = disc.ultimaAttivita ?? disc.creata { Text("· " + d.formatted(date: .abbreviated, time: .shortened)) }
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
                            if let d = p.data { Text("· " + d.formatted(date: .abbreviated, time: .shortened)) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Text(p.testo).font(.callout).textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(discussione.titolo)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await posts.loadIfNeeded { try await app.services.ariel.discussione(discussione) } }
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
