import SwiftUI

/// Altro › IA: tutte le impostazioni dei modelli (trascrizione, miglioramento dell'audio, riassunti) e lo stato dei
/// lavori in background. Oggi tutto gira sul dispositivo; qui andranno anche gli eventuali servizi cloud.
struct IAView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("motoreTrascrizione") private var motoreTrascrizione = MotoreTrascrizione.apple.rawValue
    @AppStorage("miglioraAudio") private var miglioraAudio = true
    @AppStorage("elaborazioneAutomatica") private var automatica = true
    @AppStorage("motoreRiassunto") private var motoreRiassunto = MotoreRiassunto.apple.rawValue

    private var motore: MotoreTrascrizione {
        let m = MotoreTrascrizione(rawValue: motoreTrascrizione) ?? .apple
        return m == .parakeet && app.parakeet.stato != .installato ? .apple : m
    }

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
            } header: {
                Text("Trascrizione")
            } footer: {
                Text(motore == .parakeet
                     ? "Parakeet riconosce più termini tecnici e nomi, mette la punteggiatura e lavora sul Neural Engine."
                     : "Parakeet è più accurato di Apple su termini tecnici e nomi, con un download di \(ParakeetLocale.dimensioneMB) MB.")
            }

            Section {
                NavigationLink { ImpostazioniRiassuntiView() } label: {
                    LabeledContent("Motore", value: MotoreRiassunto.disponibile?.nome ?? "Non disponibile")
                }
            } header: {
                Text("Riassunti")
            } footer: {
                Text(statoRiassunti.nota)
            }

            Section {
                Toggle("Trascrivi e riassumi da solo", isOn: $automatica)
            } header: {
                Text("Dopo ogni registrazione")
            } footer: {
                Text("Alla fine di una registrazione partono, uno dopo l'altro, trascrizione, riassunto e miglioramento dell'audio: quando apri la lezione è già tutto pronto.")
            }

            Section {
                Toggle("Migliora l'audio dopo ogni registrazione", isOn: $miglioraAudio)
            } header: {
                Text("Audio")
            } footer: {
                Text("Volume della voce normalizzato, fruscio e rumore di fondo attenuati, per ascoltare meglio. La trascrizione usa sempre l'audio originale, che resta conservato e si può ripristinare.")
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

    private var statoRiassunti: (testo: String, nota: String) {
        if MotoreRiassunto.disponibile == .qwen {
            return ("Qwen 3.5 4B", "Qwen lavora sulla GPU con l'app aperta: se esci, il riassunto si mette in pausa e riprende al ritorno.")
        }
        return switch AppleIntelligence.stato {
        case .disponibile:
            ("Disponibile", QwenLocale.supportato ? "Apple Intelligence sul dispositivo. Con Qwen 3.5 4B (3 GB) i riassunti sono più completi e precisi." : "Apple Intelligence sul dispositivo, aggiornato con iOS.")
        case .nonAttiva:
            ("Disattivata", "Attiva Apple Intelligence in Impostazioni › Apple Intelligence e Siri per generare i riassunti.")
        case .inPreparazione:
            ("In download", "Apple Intelligence sta scaricando il modello: i riassunti saranno disponibili tra poco.")
        case .nonSupportata:
            ("Non disponibile", "Questo iPhone o questa versione di iOS non supporta Apple Intelligence: le trascrizioni restano disponibili.")
        }
    }
}
