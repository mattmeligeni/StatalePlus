import SwiftUI

/// Selettore "Vai a data": porta alla settimana (lunedì–domenica) che contiene la data scelta.
struct VaiADataSheet: View {
    let titolo: String
    let onGo: (Date) -> Void
    @State private var data: Date
    @Environment(\.dismiss) private var dismiss

    init(titolo: String = "Vai a data", iniziale: Date = .now, onGo: @escaping (Date) -> Void) {
        self.titolo = titolo
        self.onGo = onGo
        _data = State(initialValue: iniziale)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Data", selection: $data, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "it_IT"))
                    .environment(\.calendar, Formats.calendar)
                Section {
                    LabeledContent("Settimana", value: Formats.settimana(Formats.inizioSettimana(data)))
                    Button("Oggi") { data = .now }
                }
            }
            .navigationTitle(titolo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Vai") { onGo(data); dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.large])
    }
}
