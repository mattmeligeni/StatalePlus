import QuickLook
import SwiftUI

// MARK: - Scadenze

/// Prossimi eventi e consegne di tutti i corsi (calendario myAriel), raggruppati per giorno.
struct ScadenzeArielView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            LiveSection(title: "Prossimi 21 giorni", live: app.scadenzeAriel, retry: { await app.loadScadenzeAriel(force: true) }) { eventi in
                if eventi.isEmpty {
                    Text("Nessuna scadenza o evento in calendario su myAriel.").foregroundStyle(.secondary)
                }
            }
            ForEach(giorni, id: \.giorno) { g in
                Section(Testo.maiuscolaIniziale(g.giorno.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Formats.it)))) {
                    ForEach(g.eventi) { RigaEvento(evento: $0) }
                }
            }
            UpdatedFooter(date: app.scadenzeAriel.updatedAt)
        }
        .navigationTitle("Scadenze")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.loadScadenzeAriel(force: true) }
        .task { await app.loadScadenzeAriel(force: false) }
    }

    private var giorni: [(giorno: Date, eventi: [EventoMoodle])] {
        Dictionary(grouping: app.scadenzeAriel.value ?? []) { Formats.calendar.startOfDay(for: $0.inizio) }
            .map { ($0.key, $0.value.sorted { $0.inizio < $1.inizio }) }
            .sorted { $0.0 < $1.0 }
    }
}

struct RigaEvento: View {
    let evento: EventoMoodle
    var mostraGiorno = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: simbolo).foregroundStyle(evento.scaduto ? Color.red : .accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(evento.nome).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                if let c = evento.corso { Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 6) {
                    Text(mostraGiorno ? Formats.giornoEOra(evento.inizio) : Formats.time(evento.inizio))
                    if let l = evento.luogo { Text("· \(l)") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if evento.scaduto {
                    Text("IN RITARDO").font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: Capsule())
                }
            }
        }
    }

    private var simbolo: String {
        switch evento.modulo {
        case "assign": "tray.and.arrow.up"
        case "quiz": "questionmark.circle"
        case "forum": "bubble.left.and.bubble.right"
        default: evento.tipo == "course" ? "calendar" : "calendar.badge.clock"
        }
    }
}

// MARK: - Notifiche

/// Notifiche di myAriel (nuovi post nei forum seguiti, valutazioni, consegne…). Aprirne una la segna come letta,
/// come sul sito: quelle dei forum aprono la discussione nell'app, le altre mostrano il testo completo.
struct NotificheArielView: View {
    @Environment(AppModel.self) private var app
    @State private var discussione: DiscussioneForum?
    @State private var espanse: Set<Int> = []

    var body: some View {
        List {
            LiveSection(title: "Notifiche", live: app.notificheAriel, retry: { await app.loadNotificheAriel() }) { n in
                if n.notifiche.isEmpty {
                    Text("Nessuna notifica su myAriel.").foregroundStyle(.secondary)
                }
                ForEach(n.notifiche) { notifica in
                    Button { apri(notifica) } label: {
                        RigaNotifica(notifica: notifica, completa: espanse.contains(notifica.id), apreDiscussione: notifica.discussione != nil)
                    }
                    .tint(.primary)
                }
            }
            UpdatedFooter(date: app.notificheAriel.updatedAt)
        }
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.loadNotificheAriel() }
        .task { if app.notificheAriel.updatedAt == nil { await app.loadNotificheAriel() } }
        .navigationDestination(item: $discussione) { DiscussionView(discussione: $0) }
    }

    private func apri(_ n: NotificaMoodle) {
        if !n.letta { Task { await app.segnaNotificaLetta(n) } }
        if let d = n.discussione {
            discussione = d
        } else if espanse.contains(n.id) {
            espanse.remove(n.id)
        } else {
            espanse.insert(n.id)
        }
    }
}

private struct RigaNotifica: View {
    let notifica: NotificaMoodle
    let completa: Bool
    let apreDiscussione: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(notifica.letta ? Color.clear : .accentColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(notifica.oggetto).font(.subheadline.weight(notifica.letta ? .regular : .semibold))
                    .multilineTextAlignment(.leading)
                if let t = notifica.testo, t != notifica.oggetto {
                    Text(t).font(.caption).foregroundStyle(.secondary).lineLimit(completa ? nil : 3)
                }
                Text(notifica.creata.relativoItaliano).font(.caption2).foregroundStyle(.secondary)
            }
            if apreDiscussione {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Materiali del corso

/// "Scaricamento contenuti del corso" di myAriel: uno zip con tutti i materiali (esclusi i file oltre 50 MB),
/// da aprire con Quick Look o salvare in File con la condivisione.
struct MaterialiCorsoSection: View {
    let courseId: String
    let titolo: String
    @Environment(AppModel.self) private var app
    @State private var inCorso = false
    @State private var zip: URL?
    @State private var errore: String?
    @State private var anteprima: URL?

    var body: some View {
        Section {
            if let zip {
                Button { anteprima = zip } label: { RigaIcona("Apri lo zip dei materiali", simbolo: "doc.zipper") }
                ShareLink(item: zip) { RigaIcona("Salva in File o condividi (\(dimensione(zip)))", simbolo: "square.and.arrow.up") }
                Button("Scarica di nuovo") { Task { await scarica() } }.font(.caption).disabled(inCorso)
            } else {
                Button { Task { await scarica() } } label: {
                    HStack {
                        RigaIcona("Scarica tutti i materiali", simbolo: "arrow.down.circle")
                        Spacer()
                        if inCorso { ProgressView() }
                    }
                }
                .disabled(inCorso)
            }
            if let errore { Text(errore).font(.caption).foregroundStyle(.red) }
        } header: {
            Text("Materiali")
        } footer: {
            Text("Uno zip con tutti i contenuti scaricabili del corso, esclusi i file oltre 50 MB.")
        }
        .quickLookPreview($anteprima)
        .task { zip = esistente }
    }

    private var cartella: URL { URL.cachesDirectory.appending(path: "Materiali/\(courseId)", directoryHint: .isDirectory) }

    private var esistente: URL? {
        (try? FileManager.default.contentsOfDirectory(at: cartella, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "zip" }
    }

    private func scarica() async {
        inCorso = true
        errore = nil
        defer { inCorso = false }
        do {
            zip = try await app.services.ariel.scaricaContenuti(courseId: courseId, titolo: titolo)
        } catch {
            errore = app.message(error)
        }
    }

    private func dimensione(_ url: URL) -> String {
        let b = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }
}
