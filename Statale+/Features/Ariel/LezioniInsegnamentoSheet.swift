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
                LiveSection(title: codiceAgenda, live: lezioni, retry: load) { list in
                    let oggi = Formats.calendar.startOfDay(for: .now)
                    let visibili = mostraPassate ? list : list.filter { $0.fine >= oggi }
                    if list.isEmpty {
                        Text("Orario non ancora pubblicato").foregroundStyle(.secondary)
                    } else if visibili.isEmpty {
                        Text("Nessuna lezione futura").foregroundStyle(.secondary)
                    }
                    if list.contains(where: { $0.fine < oggi }) {
                        Toggle("Mostra lezioni passate", isOn: $mostraPassate)
                    }
                    ForEach(visibili) { l in
                        Button { selected = l } label: { LezioneRow(lezione: l, mostraData: true) }.tint(.primary)
                    }
                }
            }
            .navigationTitle(titolo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .refreshable { await load() }
            .task { await lezioni.loadIfNeeded { try await fetch() } }
            .sheet(item: $selected) { LezioneDetail(lezione: $0).presentationDetents([.medium, .large]) }
        }
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
