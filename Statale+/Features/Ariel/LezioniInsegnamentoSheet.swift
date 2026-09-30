import SwiftUI

/// Lezioni di un solo insegnamento dalle API Agenda. Il codice Ariel coincide con quello Agenda
/// (Ariel "DBD-29" → Agenda "DBD-29_1", file "2026/DBD-29_1_1-semestre.xml").
struct LezioniInsegnamentoSheet: View {
    let titolo: String
    let codiceAgenda: String
    let anno: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var lezioni = Live<[Lezione]>()
    @State private var mostraPassate = false
    @State private var selected: Lezione?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(titolo).font(.headline).fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                if let list = lezioni.value {
                    let oggi = Formats.calendar.startOfDay(for: .now)
                    let visibili = mostraPassate ? list : list.filter { $0.fine >= oggi }
                    Section {
                        if list.isEmpty {
                            Text("Orario non ancora pubblicato").foregroundStyle(.secondary)
                        } else if visibili.isEmpty {
                            Text("Nessuna lezione futura").foregroundStyle(.secondary)
                        }
                        if list.contains(where: { $0.fine < oggi }) {
                            Toggle("Mostra lezioni passate", isOn: $mostraPassate)
                        }
                    }
                    // Righe compatte raggruppate per mese: il nome della materia è già in alto.
                    ForEach(mesi(visibili), id: \.inizio) { mese in
                        Section(mese.inizio.formatted(.dateTime.month(.wide).year().locale(Formats.it)).capitalized) {
                            ForEach(mese.lezioni) { l in
                                Button { selected = l } label: { LezioneCompattaRow(lezione: l) }.tint(.primary)
                            }
                        }
                    }
                    if let e = lezioni.error { Section { ErrorRow(message: e, retry: load) } }
                } else {
                    LiveSection(title: "Lezioni", live: lezioni, retry: load) { _ in EmptyView() }
                }
            }
            .navigationTitle("Calendario lezioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .refreshable { await load() }
            .task { await lezioni.loadIfNeeded { try await fetch() } }
            .sheet(item: $selected) { LezioneDetail(lezione: $0).presentationDetents([.medium, .large]) }
        }
    }

    private func mesi(_ lezioni: [Lezione]) -> [(inizio: Date, lezioni: [Lezione])] {
        Dictionary(grouping: lezioni) { Formats.calendar.dateInterval(of: .month, for: $0.inizio)?.start ?? $0.inizio }
            .map { ($0.key, $0.value.sorted { $0.inizio < $1.inizio }) }
            .sorted { $0.0 < $1.0 }
    }

    private func load() async { await lezioni.load { try await fetch() } }

    /// File XML: dall'elenco insegnamenti già noto, altrimenti per tentativi sui periodi.
    private func fetch() async throws -> [Lezione] {
        if let ins = app.agenda?.insegnamenti.values.flatMap({ $0 }).first(where: { $0.codice == codiceAgenda }) {
            return try await app.services.agenda.lezioni(file: ins.file)
        }
        var periodi = app.agenda?.mioCorsoOrario.cdl.periodi.map(\.valore) ?? []
        for p in ["1-semestre", "2-semestre", "annuale"] where !periodi.contains(p) { periodi.append(p) }
        for p in periodi {
            let found = try await app.services.agenda.lezioni(file: "\(anno)/\(codiceAgenda)_\(p).xml")
            if !found.isEmpty { return found.sorted { $0.inizio < $1.inizio } }
        }
        return []
    }
}

/// Riga di una lezione senza il nome della materia: giorno, orario, aula e sede, stato.
private struct LezioneCompattaRow: View {
    let lezione: Lezione

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(lezione.inizio.formatted(.dateTime.weekday(.abbreviated).locale(Formats.it)).uppercased())
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(lezione.inizio.formatted(.dateTime.day().locale(Formats.it))).font(.title3.bold().monospacedDigit())
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Formats.time(lezione.inizio)) – \(Formats.time(lezione.fine))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .strikethrough(lezione.annullato)
                Text(lezione.aula).font(.caption.weight(.medium))
                Text(lezione.sede).font(.caption).foregroundStyle(.secondary)
                TimeStatusBadge(inizio: lezione.inizio, fine: lezione.fine, annullato: lezione.annullato)
            }
            Spacer(minLength: 0)
        }
        .opacity(lezione.annullato ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }
}
