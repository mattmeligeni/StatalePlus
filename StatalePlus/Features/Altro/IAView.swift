import SwiftUI

/// Altro › IA: scelta dei modelli per trascrizione e riassunti, miglioramento dell'audio, catena automatica.
struct IAView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("motoreTrascrizione") private var motoreTrascrizione = MotoreTrascrizione.apple.rawValue
    @AppStorage("miglioraAudio") private var miglioraAudio = true
    @AppStorage("elaborazioneAutomatica") private var automatica = true
    @AppStorage("motoreRiassunto") private var motoreRiassunto = MotoreRiassunto.cloud.rawValue

    private var motore: MotoreTrascrizione {
        let m = MotoreTrascrizione(rawValue: motoreTrascrizione) ?? .apple
        return m == .parakeet && app.parakeet.stato != .installato ? .apple : m
    }

    var body: some View {
        List {
            Section {
                Label(MotoreRiassunto.disponibile == .cloud
                      ? "L'audio resta sempre sul telefono. Per riassunti e glossario il testo va ad Apple Intelligence, che non lo conserva."
                      : "Tutto funziona sul telefono, anche offline: audio e testi delle lezioni non vengono inviati a nessuno.",
                      systemImage: "lock.shield")
                    .font(.callout)
            }

            Section {
                NavigationLink { ImpostazioniTrascrizioneView() } label: {
                    LabeledContent("Trascrizione", value: motore.nome)
                }
                NavigationLink { ImpostazioniRiassuntiView() } label: {
                    LabeledContent("Riassunti", value: motoreRiassunti)
                }
                NavigationLink { GlossarioView() } label: {
                    LabeledContent("Glossario del corso", value: app.glossario.attuale.map { "\($0.termini.count) termini" } ?? "Da creare")
                }
            } header: {
                Text("Modelli")
            } footer: {
                if let nota = notaRiassunti { Text(nota) }
            }

            Section {
                Toggle("Trascrivi e riassumi da solo", isOn: $automatica)
            } header: {
                Text("Dopo ogni registrazione")
            } footer: {
                Text("Alla fine di una registrazione partono da soli trascrizione e riassunto.")
            }

            Section {
                Toggle("Migliora l'audio dopo ogni registrazione", isOn: $miglioraAudio)
            } header: {
                Text("Audio")
            } footer: {
                Text("Alza il volume della voce e riduce il rumore di fondo, solo per l'ascolto: la trascrizione usa sempre l'audio originale, che si può ripristinare.")
            }

            Section {
                Button { app.mostraPresentazione = true } label: {
                    Label("Rivedi la presentazione", systemImage: "rectangle.stack")
                }
            } footer: {
                Text("Le funzioni principali dell'app e come usare trascrizioni, riassunti e glossario.")
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Modelli online").foregroundStyle(.secondary)
                        Text("Prossimamente").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cloud").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Più veloci e potenti, ma audio e testi verrebbero inviati fuori dal telefono.")
            }
        }
        .navigationTitle("IA")
        .onAppear {
            app.parakeet.ricontrolla()
            app.qwen.ricontrolla()
        }
    }

    private var motoreRiassunti: String {
        _ = motoreRiassunto
        _ = app.qwen.stato
        return MotoreRiassunto.disponibile?.nome ?? (QwenLocale.supportato ? "Da scaricare" : "Non disponibile")
    }

    private var notaRiassunti: String? {
        if MotoreRiassunto.disponibile == .qwen { return nil }
        switch AppleIntelligence.stato {
        case .disponibile: return nil
        case .nonSupportata: return QwenLocale.supportato ? "Per i riassunti scarica il modello da Riassunti." : nil
        case .nonAttiva: return "Per i riassunti con Apple Intelligence attivala in Impostazioni › Apple Intelligence e Siri, oppure scarica il modello da Riassunti."
        case .inPreparazione: return "Apple Intelligence sta scaricando il suo modello: i riassunti arrivano tra poco."
        }
    }
}
