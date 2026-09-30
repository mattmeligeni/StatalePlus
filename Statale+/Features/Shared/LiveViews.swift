import SwiftUI

/// Banner "aggiornato alle HH:MM".
struct UpdatedFooter: View {
    let date: Date?
    var body: some View {
        if let date {
            Text("Aggiornato alle \(Formats.time(date))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Contenuto di una sezione live: caricamento, errore con riprova, oppure il valore.
struct LiveSection<Value, Content: View>: View {
    let title: String
    let live: Live<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        Section {
            if let value = live.value {
                content(value)
            } else if let error = live.error {
                ErrorRow(message: error, retry: retry)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            if live.value != nil, let error = live.error {
                ErrorRow(message: error, retry: retry)
            }
        } header: {
            Text(title)
        }
    }
}

struct ErrorRow: View {
    let message: String
    let retry: () async -> Void
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout)
            Spacer()
            Button("Riprova") { Task { await retry() } }.buttonStyle(.borderless)
        }
    }
}

/// Etichetta di stato aggiornata ogni minuto: ANNULLATA, IN CORSO, INIZIA TRA X MIN (da 60 minuti prima).
struct TimeStatusBadge: View {
    let inizio: Date
    let fine: Date?
    var annullato = false
    /// Ora di riferimento fornita dal chiamante (Oggi, preview); se nil usa l'ora reale, aggiornata ogni minuto.
    var adesso: Date?

    var body: some View {
        if let adesso {
            etichetta(at: adesso)
        } else {
            TimelineView(.everyMinute) { ctx in etichetta(at: ctx.date) }
        }
    }

    private enum Tipo: Equatable { case annullata, inCorso, iniziaTra }

    /// Cambio di stato in dissolvenza (con leggero ridimensionamento); i minuti del conto alla rovescia
    /// cambiano con l'animazione numerica.
    private func etichetta(at now: Date) -> some View {
        let s = status(at: now)
        return ZStack(alignment: .leading) {
            if let s {
                Text(s.text)
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(s.color, in: Capsule())
                    .id(s.tipo)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: s?.tipo)
        .animation(.snappy, value: s?.text)
    }

    private func status(at now: Date) -> (text: String, color: Color, tipo: Tipo)? {
        if annullato { return ("ANNULLATA", .red, .annullata) }
        let end = fine ?? inizio.addingTimeInterval(2 * 3600)
        if now >= inizio && now < end { return ("IN CORSO", .purple, .inCorso) }
        let minuti = Int((inizio.timeIntervalSince(now) / 60).rounded(.up))
        if minuti > 0 && minuti <= 60 { return ("INIZIA TRA \(minuti) MIN", .orange, .iniziaTra) }
        return nil
    }
}

/// Riga di una lezione (Oggi, Orario, calendario insegnamento).
struct LezioneRow: View {
    enum Enfasi { case normale, prossima, passata }

    let lezione: Lezione
    var mostraData = false
    var enfasi: Enfasi = .normale
    var adesso: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing) {
                if mostraData {
                    Text(lezione.inizio.formatted(.dateTime.day().month(.abbreviated).locale(Formats.it)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(Formats.time(lezione.inizio)).font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(enfasi == .prossima ? Color.accentColor : .primary)
                Text(Formats.time(lezione.fine)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 52, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(lezione.insegnamento)
                    .font(enfasi == .prossima ? .headline : .subheadline.weight(enfasi == .normale ? .semibold : .regular))
                    .strikethrough(lezione.annullato)
                    .lineLimit(2)
                Label("\(lezione.aula) · \(lezione.sede)", systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(.secondary)
                TimeStatusBadge(inizio: lezione.inizio, fine: lezione.fine, annullato: lezione.annullato, adesso: adesso)
                if !lezione.note.isEmpty {
                    Text(lezione.note).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .opacity(lezione.annullato ? 0.7 : (enfasi == .passata ? 0.55 : 1))
        .accessibilityElement(children: .combine)
    }
}

/// Pulsante che apre Mappe sull'indirizzo dell'aula ricavato da EasyRoom.
struct MapsButton<Label: View>: View {
    let aula: String
    let sede: String
    var codici: [String] = []
    @ViewBuilder let label: () -> Label
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var loading = false

    var body: some View {
        Button {
            loading = true
            Task {
                if let url = await app.mapsURL(aula: aula, sede: sede, codici: codici) { openURL(url) }
                loading = false
            }
        } label: {
            HStack { label(); if loading { ProgressView().controlSize(.small) } }
        }
        .disabled(loading)
    }
}

/// Selettore a pillole orizzontale (periodi didattici, anni di corso).
struct PillPicker<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let selected: Item?
    let title: (Item) -> String
    let onSelect: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let on = item == selected
                    Button { onSelect(item) } label: {
                        Text(title(item))
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Avatar circolare con la foto profilo locale o le iniziali.
struct ProfileAvatar: View {
    let size: CGFloat
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let img = app.photo.image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                let iniziali = (app.studente?.nome ?? "").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
                ZStack {
                    Circle().fill(Color.accentColor.gradient)
                    Text(iniziali.isEmpty ? "?" : iniziali).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
