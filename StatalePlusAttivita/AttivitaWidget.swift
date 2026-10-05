import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AttivitaBundle: WidgetBundle {
    var body: some Widget {
        AttivitaElaborazioneWidget()
    }
}

/// Live Activity dei lavori lunghi di Statale+: download dei modelli, trascrizioni, riassunti e miglioramento
/// dell'audio. Un'unica attività con tutti i lavori in corso, il primo in evidenza.
struct AttivitaElaborazioneWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AttivitaElaborazioneAttributes.self) { context in
            SchermataBlocco(lavori: context.state.lavori)
                .padding(16)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            let principale = context.state.lavori.first
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let principale {
                        Image(systemName: Aspetto.simbolo(principale)).font(.title2).foregroundStyle(Aspetto.colore(principale))
                            .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let principale {
                        Text(Aspetto.percentuale(principale)).font(.title3.monospacedDigit().weight(.semibold))
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let principale {
                        VStack(spacing: 2) {
                            Text(principale.titolo).font(.headline).lineLimit(1)
                            Text(principale.sottotitolo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let principale {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: principale.progresso).tint(Aspetto.colore(principale))
                            Text(Aspetto.dettaglio(principale)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if context.state.lavori.count > 1 {
                                Text("e altri \(context.state.lavori.count - 1) in coda").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                if let principale {
                    Image(systemName: Aspetto.simbolo(principale)).foregroundStyle(Aspetto.colore(principale))
                }
            } compactTrailing: {
                if let principale {
                    Text(Aspetto.percentuale(principale)).font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Aspetto.colore(principale))
                }
            } minimal: {
                if let principale {
                    ProgressView(value: principale.progresso) {
                        Image(systemName: Aspetto.simbolo(principale)).font(.caption2)
                    }
                    .progressViewStyle(.circular)
                    .tint(Aspetto.colore(principale))
                }
            }
        }
    }
}

private struct SchermataBlocco: View {
    let lavori: [AttivitaElaborazioneAttributes.Lavoro]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill").font(.caption)
                Text("Statale+").font(.caption.weight(.semibold))
                Spacer()
                if lavori.count > 1 { Text("\(lavori.count) lavori").font(.caption).foregroundStyle(.secondary) }
            }
            .foregroundStyle(.secondary)
            ForEach(lavori.prefix(3)) { RigaLavoro(lavoro: $0) }
        }
    }
}

private struct RigaLavoro: View {
    let lavoro: AttivitaElaborazioneAttributes.Lavoro

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Aspetto.simbolo(lavoro))
                .font(.title3)
                .foregroundStyle(Aspetto.colore(lavoro))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(lavoro.titolo).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Aspetto.percentuale(lavoro)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(lavoro.sottotitolo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !lavoro.concluso {
                    ProgressView(value: lavoro.progresso).tint(Aspetto.colore(lavoro))
                }
                Text(Aspetto.dettaglio(lavoro)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private enum Aspetto {
    static func simbolo(_ l: AttivitaElaborazioneAttributes.Lavoro) -> String {
        if l.concluso { return "checkmark.circle.fill" }
        if l.inPausa { return "pause.circle.fill" }
        return switch l.tipo {
        case "download": "arrow.down.circle.fill"
        case "trascrizione": "waveform"
        case "riassunto": "text.badge.star"
        case "miglioramento": "wand.and.stars"
        default: "gearshape.2.fill"
        }
    }

    static func colore(_ l: AttivitaElaborazioneAttributes.Lavoro) -> Color {
        if l.concluso { return .green }
        if l.inPausa { return .orange }
        return switch l.tipo {
        case "riassunto": .purple
        case "miglioramento": .teal
        default: .blue
        }
    }

    static func percentuale(_ l: AttivitaElaborazioneAttributes.Lavoro) -> String {
        l.concluso ? "Fatto" : "\(Int((l.progresso * 100).rounded()))%"
    }

    static func dettaglio(_ l: AttivitaElaborazioneAttributes.Lavoro) -> String {
        if l.concluso { return "Completato" }
        if l.inPausa { return "In pausa: riprende quando torni nell'app" }
        return [l.fase, l.rimanente].compactMap { $0 }.joined(separator: " · ")
    }
}
