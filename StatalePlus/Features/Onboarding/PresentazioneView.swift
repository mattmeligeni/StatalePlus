import SwiftUI

/// Presentazione dopo il primo accesso: quattro pagine da scorrere sulle funzioni principali, soprattutto quelle con
/// l'IA, con i pulsanti per scaricare Parakeet e creare il glossario senza dover cercare nelle impostazioni.
/// Stesso stile della conferma di download dei modelli. Si rivede da Altro › IA.
struct PresentazioneView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var pagina = 0
    @State private var confermaParakeet = false

    private let ultima = 3

    var body: some View {
        NavigationStack {
            TabView(selection: $pagina) {
                benvenuto.tag(0)
                registrazioni.tag(1)
                intelligenza.tag(2)
                glossario.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { barra }
            .toolbar {
                // Sempre presente e solo nascosto sull'ultima pagina: toglierlo ricomponeva la barra durante lo
                // scorrimento dalla terza alla quarta pagina, che andava a scatti.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salta", action: chiudi)
                        .opacity(pagina < ultima ? 1 : 0)
                        .disabled(pagina >= ultima)
                        .accessibilityHidden(pagina >= ultima)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $confermaParakeet) {
            ConfermaDownloadModello(
                modello: app.parakeet.modello,
                titolo: "Scaricare Parakeet?",
                testo: "Trascrizioni più precise, sul telefono. Il download si fa una volta sola.",
                consumi: "Due ore di lezione in pochi minuti, con poca batteria."
            ) { app.parakeet.scarica() }
            .presentationDetents([.large])
        }
    }

    // MARK: Pagine

    private var benvenuto: some View {
        Pagina(simbolo: "graduationcap.fill", titolo: "Benvenuto in Statale Plus",
               testo: "Tutti i servizi per chi studia alla Statale, in un'app sola e con un solo accesso.") {
            Section {
                Voce(simbolo: "sun.max", titolo: "Oggi",
                     testo: "Le lezioni del giorno con aula e orario, l'esame prenotato più vicino e gli avvisi di Ariel.")
                Voce(simbolo: "calendar", titolo: "Orario",
                     testo: "L'orario del tuo corso per settimana e semestre, con le aule libere.")
                Voce(simbolo: "checkmark.seal", titolo: "Presenze",
                     testo: "Registra la presenza con il codice della lezione o il QR e controlla la frequenza (Altro › Presenze).")
                Voce(simbolo: "graduationcap", titolo: "Esami e carriera",
                     testo: "Calendario degli appelli, prenotazioni, libretto e tasse (in Altro).")
                Voce(simbolo: "books.vertical", titolo: "Ariel",
                     testo: "Siti dei corsi, materiali, avvisi e scadenze, senza aprire il browser.")
            }
        }
    }

    private var registrazioni: some View {
        Pagina(simbolo: "waveform", titolo: "Registra le lezioni",
               testo: "Registra la lezione e ritrovala ordinata per insegnamento, pronta da riascoltare e da studiare.") {
            Section {
                Voce(simbolo: "record.circle", titolo: "Come si avvia",
                     testo: "Dalla scheda Registrazioni con «Avvia registrazione», oppure da Oggi con «Inizia registrazione» sulla lezione in corso.")
                Voce(simbolo: "lock.iphone", titolo: "Anche a schermo bloccato",
                     testo: "La registrazione continua con il telefono in tasca. Puoi aggiungere segnalibri nei punti importanti.")
                Voce(simbolo: "speaker.wave.2", titolo: "Audio più chiaro",
                     testo: "Dopo ogni registrazione la voce si alza e il rumore di fondo si riduce, solo per l'ascolto.")
                Voce(simbolo: "lock.shield", titolo: "Resta sul telefono",
                     testo: "Audio, trascrizioni e riassunti non vengono inviati a nessuno.")
            }
        }
    }

    private var intelligenza: some View {
        Pagina(simbolo: "apple.intelligence", titolo: "Trascrizioni e riassunti",
               testo: "Alla fine di ogni registrazione l'app trascrive la lezione e ne scrive il riassunto da sola, anche se esci dall'app.") {
            Section {
                Voce(simbolo: "text.quote", titolo: "Trascrizione",
                     testo: "Funziona subito con il riconoscimento vocale di iPhone. Qui sotto, o più avanti nelle impostazioni della trascrizione, puoi scaricare un modello più preciso, soprattutto con termini tecnici e nomi, con la stessa velocità e la stessa privacy di quello integrato.")
                Voce(simbolo: "sparkles", titolo: "Riassunto",
                     testo: "Apple Intelligence scrive gli appunti della lezione, con punti chiave e domande di ripasso.")
                Voce(simbolo: "lock.iphone", titolo: "Puoi uscire dall'app",
                     testo: "Il lavoro continua in background e lo segui dalla schermata di blocco.")
            } footer: {
                if let nota = notaAppleIntelligence { Text(nota) }
            }
            Section {
                switch app.parakeet.stato {
                case .installato:
                    Label("Il modello più preciso è scaricato e viene usato per le trascrizioni.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .download(let p):
                    ProgressView(value: p) { Text("Download del modello più preciso…").font(.callout) }
                case .assente:
                    Button { confermaParakeet = true } label: {
                        Label("Scarica il modello più preciso (\(ParakeetLocale.dimensioneMB) MB)", systemImage: "arrow.down.circle")
                    }
                }
            } footer: {
                Text("Si scarica dentro Statale Plus, non è un'altra app. Puoi cambiare modello quando vuoi da Altro › IA › Trascrizione.")
            }
        }
    }

    private var glossario: some View {
        Pagina(simbolo: "character.book.closed", titolo: "Il glossario del corso",
               testo: "Le trascrizioni automatiche a volte storpiano i termini tecnici («dopamila» invece di «dopamina»). Il glossario li corregge.") {
            Section {
                Voce(simbolo: "wand.and.stars", titolo: "Si crea in un minuto",
                     testo: "Apple Intelligence raccoglie i termini degli insegnamenti del tuo corso.")
                Voce(simbolo: "arrow.triangle.2.circlepath", titolo: "Impara dalle lezioni",
                     testo: "A ogni riassunto aggiunge i termini che incontra e ricorregge la trascrizione.")
                Voce(simbolo: "pencil", titolo: "Puoi modificarlo",
                     testo: "Aggiungi o togli termini e correggi le trascrizioni già fatte da Altro › IA › Glossario del corso.")
            }
            Section {
                if case .creazione(let p) = app.glossario.stato {
                    ProgressView(value: p) { Text("Creazione del glossario…").font(.callout) }
                } else if let g = app.glossario.attuale {
                    Label("Glossario pronto: \(g.termini.count) termini.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if app.glossario.motore != nil {
                    Button { app.creaGlossario() } label: { Label("Crea il glossario ora", systemImage: "wand.and.stars") }
                } else {
                    Text("Per crearlo serve Apple Intelligence: attivala in Impostazioni › Apple Intelligence e Siri.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Tutte le impostazioni dell'intelligenza artificiale sono in Altro › IA, dove puoi anche rivedere questa presentazione.")
            }
        }
    }

    // MARK: Pulsanti

    private var barra: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0...ultima, id: \.self) { i in
                    Circle().fill(i == pagina ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Button {
                if pagina < ultima { withAnimation { pagina += 1 } } else { chiudi() }
            } label: {
                Text(pagina < ultima ? "Avanti" : "Inizia").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.bar)
    }

    private var notaAppleIntelligence: String? {
        switch AppleIntelligence.stato {
        case .disponibile: nil
        case .nonAttiva: "Per i riassunti attiva Apple Intelligence in Impostazioni › Apple Intelligence e Siri."
        case .inPreparazione: "Apple Intelligence sta scaricando il suo modello: i riassunti arrivano tra poco."
        case .nonSupportata: "Su questo iPhone i riassunti non sono disponibili; la trascrizione sì."
        }
    }

    private func chiudi() {
        Preferenze.presentazioneVista = true
        dismiss()
    }
}

/// Una pagina della presentazione: intestazione con icona grande, come la conferma di download dei modelli.
private struct Pagina<Contenuto: View>: View {
    let simbolo: String
    let titolo: String
    let testo: String
    @ViewBuilder let contenuto: Contenuto

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: simbolo).font(.system(size: 44)).foregroundStyle(Color.accentColor)
                    Text(titolo).font(.title2.bold())
                    Text(testo).font(.callout)
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }
            contenuto
        }
    }
}

private struct Voce: View {
    let simbolo: String
    let titolo: String
    let testo: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(titolo).font(.subheadline.weight(.semibold))
                Text(testo).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: simbolo).foregroundStyle(Color.accentColor)
        }
    }
}
