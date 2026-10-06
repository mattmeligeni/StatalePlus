import SwiftUI

/// Nota di disclaimer e copyright in fondo ad Altro.
struct Disclaimer: View {
    private var versione: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Statale+ \(versione)").font(.footnote.weight(.semibold))
            Text("© 2026 Mattia Meligeni. Tutti i diritti riservati.")
            Text("""
                Statale+ è un'app indipendente e non ufficiale: non è affiliata, sponsorizzata né approvata \
                dall'Università degli Studi di Milano. Nomi e marchi dei servizi citati appartengono ai rispettivi \
                titolari. I dati sono letti dai servizi dell'Ateneo e potrebbero non essere aggiornati: \
                in caso di dubbio fa fede sempre il sito ufficiale.
                """)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Servizi, dati e tecnologie usati dall'app, con i relativi link.
struct CreditiView: View {
    private struct Voce: Identifiable {
        var id: String { nome }
        let nome: String
        let descrizione: String
        let link: String
    }

    private let sezioni: [(titolo: String, voci: [Voce])] = [
        ("Ateneo", [
            Voce(nome: "Università degli Studi di Milano", descrizione: "Ateneo", link: "https://www.unimi.it"),
            Voce(nome: "UNIMIA", descrizione: "Portale studenti: profilo, carriera, tasse", link: "https://unimia.unimi.it"),
            Voce(nome: "SIFA online", descrizione: "Servizi di segreteria: esami, verbalizzazione, pagamenti", link: "https://studente.unimi.it"),
            Voce(nome: "Ariel", descrizione: "Portale della didattica online", link: "https://ariel.unimi.it"),
            Voce(nome: "myAriel", descrizione: "Siti dei corsi", link: "https://myariel.unimi.it"),
            Voce(nome: "Agenda web – orari e appelli", descrizione: "Orario delle lezioni, calendario appelli, aule", link: "https://orari.unimi.it"),
        ]),
        ("Piattaforme", [
            Voce(nome: "Moodle", descrizione: "Piattaforma su cui è basato myAriel", link: "https://moodle.org"),
            Voce(nome: "EasyStaff – EasyAcademy", descrizione: "Agenda, EasyRoom (aule) ed EasyBadge (presenze)", link: "https://www.easystaff.it"),
        ]),
        ("Tecnologie Apple", [
            Voce(nome: "Swift e SwiftUI", descrizione: "Linguaggio e interfaccia dell'app", link: "https://developer.apple.com/swiftui/"),
            Voce(nome: "Speech", descrizione: "Trascrizione delle registrazioni", link: "https://developer.apple.com/documentation/speech"),
            Voce(nome: "Parakeet TDT 0.6B v3 (NVIDIA)", descrizione: "Trascrizione · licenza CC BY 4.0 (versione Ultra di moondream)", link: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3"),
            Voce(nome: "FluidAudio (Fluid Inference)", descrizione: "Esegue Parakeet sul telefono · licenza Apache 2.0", link: "https://github.com/FluidInference/FluidAudio"),
            Voce(nome: "Apple Intelligence – Foundation Models", descrizione: "Riassunti delle lezioni sul dispositivo", link: "https://developer.apple.com/documentation/foundationmodels"),
            Voce(nome: "Writing Tools", descrizione: "Revisione di trascrizioni e riassunti", link: "https://developer.apple.com/apple-intelligence/"),
            Voce(nome: "AVFoundation", descrizione: "Registrazione, riproduzione e scansione QR", link: "https://developer.apple.com/documentation/avfoundation"),
            Voce(nome: "Mappe", descrizione: "Indicazioni per aule e sedi", link: "https://maps.apple.com"),
        ]),
    ]

    var body: some View {
        List {
            ForEach(sezioni, id: \.titolo) { sezione in
                Section(sezione.titolo) {
                    ForEach(sezione.voci) { v in
                        if let url = URL(string: v.link) {
                            Link(destination: url) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(v.nome).foregroundStyle(.primary)
                                        Text(v.descrizione).font(.caption).foregroundStyle(.secondary)
                                        Text(url.host() ?? v.link).font(.caption2).foregroundStyle(Color.accentColor)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square").foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Crediti")
    }
}
