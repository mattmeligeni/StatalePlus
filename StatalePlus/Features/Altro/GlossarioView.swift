import SwiftUI

/// Altro › IA › Glossario del corso: parole del corso usate per correggere le trascrizioni.
struct GlossarioView: View {
    @Environment(AppModel.self) private var app
    @State private var nuovo = ""
    @State private var cerca = ""
    @State private var esito: String?
    @State private var confermaElimina = false

    private var gestore: GestoreGlossario { app.glossario }
    private var termini: [String] {
        let tutti = gestore.glossario?.termini ?? []
        return cerca.isEmpty ? tutti : tutti.filter { $0.localizedCaseInsensitiveContains(cerca) }
    }

    var body: some View {
        List {
            Section {
                Text("Corregge le parole storpiate dalla trascrizione, ad esempio «dopamila» in «dopamina». Cambia solo parole che il dizionario non conosce e che sono quasi uguali a un termine del corso.")
                    .font(.callout)
            }

            Section {
                if case .creazione(let p) = gestore.stato {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: p) { Text("Creazione del glossario…").font(.callout) }
                        Button("Annulla", role: .destructive) { gestore.annulla() }.font(.callout).buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                } else {
                    if let g = gestore.glossario {
                        LabeledContent("Termini", value: "\(g.termini.count)")
                        if let n = g.imparati?.count, n > 0 { LabeledContent("Imparati dalle lezioni", value: "\(n)") }
                        LabeledContent("Creato", value: "\(g.generatoIl.italiano(date: .abbreviated, time: .omitted)) · \(g.modello)")
                    }
                    Button(gestore.glossario == nil ? "Crea il glossario" : "Aggiorna il glossario") { crea() }
                        .disabled(app.studente == nil)
                }
                if let e = gestore.errore {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text(app.studente.map { Testo.nomeCorso($0.corso) } ?? "Corso")
            } footer: {
                Text(notaMotore)
            }

            Section {
                HStack {
                    TextField("Aggiungi un termine", text: $nuovo)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(aggiungi)
                    Button("Aggiungi", action: aggiungi).disabled(nuovo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if gestore.glossario != nil {
                    Button("Correggi le trascrizioni già fatte") {
                        let r = gestore.correggiTrascrizioni(in: app.recordings)
                        esito = r.parole == 0 ? "Nessuna parola da correggere." : "Corrette \(r.parole) parole in \(r.trascrizioni) trascrizioni."
                    }
                }
                if let esito { Text(esito).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("Le nuove trascrizioni si correggono da sole, e il glossario si arricchisce con i termini delle lezioni riassunte.")
            }

            if !termini.isEmpty || !cerca.isEmpty {
                Section("Termini") {
                    ForEach(termini, id: \.self) { Text($0) }
                        .onDelete { indici in gestore.rimuovi(indici.map { termini[$0] }) }
                }
            }

            if gestore.glossario != nil {
                Section {
                    Button("Elimina il glossario", role: .destructive) { confermaElimina = true }
                }
            }
        }
        .searchable(text: $cerca, prompt: "Cerca un termine")
        .autocorrectionDisabled()
        .tastieraConChiudi()
        .navigationTitle("Glossario del corso")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { gestore.ricarica() }
        .confirmationDialog("Eliminare il glossario?", isPresented: $confermaElimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { gestore.elimina() }
        } message: {
            Text("Le trascrizioni già corrette restano così.")
        }
    }

    private var notaMotore: String {
        switch gestore.motore {
        case .cloud: "Creato con Apple Intelligence online dai nomi del corso e degli insegnamenti. Puoi aggiungere o togliere termini."
        case .apple: "Creato con Apple Intelligence dai nomi del corso e degli insegnamenti. Puoi aggiungere o togliere termini."
        case nil: "Per crearlo attiva Apple Intelligence. Intanto puoi aggiungere termini a mano."
        }
    }

    private func crea() { app.creaGlossario() }

    private func aggiungi() {
        gestore.aggiungi(nuovo)
        nuovo = ""
    }
}
