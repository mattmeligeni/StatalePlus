import SwiftUI

/// Altro › IA: tutte le impostazioni dei modelli (trascrizione, miglioramento dell'audio, riassunti) e lo stato dei
/// lavori in background. Oggi tutto gira sul dispositivo; qui andranno anche gli eventuali servizi cloud.
struct IAView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("motoreTrascrizione") private var motoreTrascrizione = MotoreTrascrizione.apple.rawValue
    @AppStorage("miglioraAudio") private var miglioraAudio = true

    private var motore: MotoreTrascrizione { MotoreTrascrizione(rawValue: motoreTrascrizione) ?? .apple }

    var body: some View {
        List {
            Section {
                Label {
                    Text("Trascrizioni, miglioramento dell'audio e riassunti funzionano sul dispositivo: audio e testi delle lezioni non lasciano l'iPhone.")
                        .font(.callout)
                } icon: {
                    Image(systemName: "lock.shield").foregroundStyle(Color.accentColor)
                }
            }

            Section {
                NavigationLink { ImpostazioniTrascrizioneView() } label: {
                    LabeledContent("Motore", value: motore.nome)
                }
                if app.whisper.stato == .installato {
                    LabeledContent("Modello Whisper", value: ByteCountFormatter.string(fromByteCount: WhisperLocale.spazioOccupato, countStyle: .file))
                }
            } header: {
                Text("Trascrizione")
            } footer: {
                Text(motore == .whisper
                     ? "Whisper è più preciso sui termini tecnici, ma più lento e pesante per la batteria."
                     : "Apple è veloce e leggero. Whisper riconosce meglio termini tecnici e nomi, con un download aggiuntivo.")
            }

            Section {
                Toggle("Migliora l'audio dopo ogni registrazione", isOn: $miglioraAudio)
            } header: {
                Text("Audio")
            } footer: {
                Text("Volume della voce normalizzato, fruscio e rumore di fondo attenuati: aiuta anche trascrizione e riassunto. L'originale resta sempre conservato e si può ripristinare dal dettaglio della registrazione.")
            }

            Section {
                LabeledContent("Modello") {
                    Text("Apple Intelligence")
                }
                LabeledContent("Stato") {
                    Text(statoRiassunti.testo).foregroundStyle(statoRiassunti.colore)
                }
            } header: {
                Text("Riassunti")
            } footer: {
                Text(statoRiassunti.nota)
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Servizi cloud").foregroundStyle(.secondary)
                        Text("Prossimamente").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cloud").foregroundStyle(.secondary)
                }
            } footer: {
                Text("In futuro potrai collegare un account di un servizio di intelligenza artificiale per trascrizioni e riassunti più rapidi delle lezioni lunghe. Finché non lo fai, tutto resta sul dispositivo.")
            }

            Section {
                Text(NotaBackground.testo).font(.callout)
            } header: {
                Text("Lavori lunghi")
            } footer: {
                Text("Trascrizioni, riassunti, miglioramento dell'audio e download dei modelli mostrano l'avanzamento anche fuori dall'app, con il tempo stimato.")
            }
        }
        .navigationTitle("IA")
    }

    private var statoRiassunti: (testo: String, colore: Color, nota: String) {
        switch AppleIntelligence.stato {
        case .disponibile:
            ("Disponibile", .green, "I riassunti usano il modello di Apple Intelligence sul dispositivo, aggiornato con iOS.")
        case .nonAttiva:
            ("Disattivata", .orange, "Attiva Apple Intelligence in Impostazioni › Apple Intelligence e Siri per generare i riassunti.")
        case .inPreparazione:
            ("In download", .orange, "Apple Intelligence sta scaricando il modello: i riassunti saranno disponibili tra poco.")
        case .nonSupportata:
            ("Non disponibile", .secondary, "Questo iPhone o questa versione di iOS non supporta Apple Intelligence: le trascrizioni restano disponibili.")
        }
    }
}
