import SwiftUI

/// EasyRoom: elenco sedi (espandibili, con aule e stato attuale) e "Dove si tiene" per la giornata odierna.
struct AuleView: View {
    private enum Mode: String, CaseIterable { case sedi = "Sedi e aule", cerca = "Dove si tiene" }
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var mode: Mode = .sedi
    @State private var query = ""
    @State private var espanse: Set<String> = []

    var body: some View {
        List {
            Picker("Modalità", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            switch mode {
            case .sedi:
                LiveSection(title: "Sedi", live: app.aule, retry: { await app.loadAule(force: true) }) { sedi($0) }
            case .cerca:
                LiveSection(title: "Solo attività di oggi, \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Formats.it)))",
                            live: app.aule, retry: { await app.loadAule(force: true) }) { cerca($0) }
            }
            UpdatedFooter(date: app.aule.updatedAt).listRowBackground(Color.clear)
        }
        .navigationTitle("Aule")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: mode == .sedi ? "Sede, aula o indirizzo" : "Insegnamento, docente o aula")
        .refreshable { await app.loadAule(force: true) }
        .task { await app.loadAule() }
    }

    // MARK: Sedi

    @ViewBuilder
    private func sedi(_ occ: OccupazioneAule) -> some View {
        let q = query.trimmed
        let perAula = Dictionary(grouping: occ.occupazioni, by: \.aulaId)
        let risultati: [(Sede, [Aula])] = occ.sedi.filter { !$0.aule.isEmpty }.compactMap { s in
            if q.isEmpty || s.nome.localizedCaseInsensitiveContains(q) || s.indirizzo.localizedCaseInsensitiveContains(q) { return (s, s.aule) }
            let aule = s.aule.filter { $0.nome.localizedCaseInsensitiveContains(q) }
            return aule.isEmpty ? nil : (s, aule)
        }
        if risultati.isEmpty { Text("Nessuna sede o aula trovata").foregroundStyle(.secondary) }
        ForEach(risultati, id: \.0.id) { sede, aule in
            DisclosureGroup(isExpanded: Binding(
                get: { espanse.contains(sede.id) || (!q.isEmpty && risultati.count <= 5) },
                set: { if $0 { espanse.insert(sede.id) } else { espanse.remove(sede.id) } })) {
                if let url = Maps.url(address: sede.indirizzo) {
                    Button { openURL(url) } label: {
                        Label(sede.indirizzo, systemImage: "map").font(.caption)
                    }
                }
                ForEach(aule) { aula in AulaRow(aula: aula, occupazioni: perAula[aula.id] ?? [], giorno: occ.giorno) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sede.nome).font(.subheadline.weight(.semibold))
                    Text("\(sede.aule.count) aule · \(sede.indirizzo)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    // MARK: Dove si tiene

    @ViewBuilder
    private func cerca(_ occ: OccupazioneAule) -> some View {
        if query.trimmed.count < 3 {
            Text("Scrivi almeno 3 lettere nella ricerca").foregroundStyle(.secondary)
        } else {
            let aule = occ.aulePerId
            let hits = occ.occupazioni.filter {
                $0.nome.localizedCaseInsensitiveContains(query) || $0.docente.localizedCaseInsensitiveContains(query)
                    || (aule[$0.aulaId]?.nome.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { $0.dalle < $1.dalle }
            if hits.isEmpty { Text("Nessuna attività trovata oggi").foregroundStyle(.secondary) }
            ForEach(hits.prefix(150)) { o in
                VStack(alignment: .leading, spacing: 3) {
                    Text(o.nome).font(.subheadline.weight(.semibold))
                    Text("\(o.dalle.prefix(5))–\(o.alle.prefix(5)) · \(o.tipo)\(o.docente.isEmpty ? "" : " · \(Testo.persona(o.docente))")").font(.caption)
                    if let a = aule[o.aulaId], let url = Maps.url(address: a.indirizzo) {
                        Button { openURL(url) } label: {
                            Label("\(a.nome) · \(a.sede)", systemImage: "mappin.and.ellipse").font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    if let r = o.intervallo(on: occ.giorno) { TimeStatusBadge(inizio: r.lowerBound, fine: r.upperBound) }
                }
            }
        }
    }
}

private struct AulaRow: View {
    let aula: Aula
    let occupazioni: [Occupazione]
    let giorno: Date

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let slots = occupazioni.compactMap { o in o.intervallo(on: giorno).map { (o, $0) } }
            let adesso = slots.first { $0.1.contains(ctx.date) }
            let prossima = slots.map(\.1.lowerBound).filter { $0 > ctx.date }.min()
            HStack {
                VStack(alignment: .leading) {
                    Text(aula.nome)
                    if let c = aula.capienza { Text("\(c) posti").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if let (o, r) = adesso {
                    VStack(alignment: .trailing) {
                        Text("occupata fino alle \(Formats.time(r.upperBound))").font(.caption).foregroundStyle(.red)
                        Text(o.nome).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text(prossima.map { "libera fino alle \(Formats.time($0))" } ?? "libera").font(.caption).foregroundStyle(.green)
                }
            }
        }
    }
}
