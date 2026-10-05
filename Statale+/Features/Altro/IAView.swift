import SwiftUI

/// Altro › IA: scelta dei modelli per trascrizione e riassunti, miglioramento dell'audio, catena automatica.
/// Oggi tutto funziona sul telefono; qui andranno anche le opzioni online.
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
                Label("Tutto funziona sul telefono, anche offline: audio e testi delle lezioni non vengono inviati a nessuno.",
                      systemImage: "lock.shield")
                    .font(.callout)
            }

            Section {
                NavigationLink { ImpostazioniTrascrizioneView() } label: {
                    LabeledContent("Modello", value: motore.nome)
                }
                NavigationLink { ImpostazioniRiassuntiView() } label: {
                    LabeledContent("Riassunti", value: MotoreRiassunto.disponibile?.nome ?? "Non disponibile")
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

    private var notaRiassunti: String? {
        switch AppleIntelligence.stato {
        case .disponibile, .nonSupportata: nil
        case .nonAttiva: "Per i riassunti con Apple Intelligence attivala in Impostazioni › Apple Intelligence e Siri."
        case .inPreparazione: "Apple Intelligence sta scaricando il suo modello: i riassunti arrivano tra poco."
        }
    }
}
