import QuickLook
import SwiftUI

/// Banner "aggiornato alle HH:MM", in una sezione propria: non si attacca mai alle righe sciolte che lo precedono.
struct UpdatedFooter: View {
    let date: Date?
    var body: some View {
        if let date {
            Section {
                Text("Aggiornato alle \(Formats.time(date))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
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
                RigaSegnaposto()
            }
            if live.value != nil, let error = live.error {
                ErrorRow(message: error, retry: retry)
            }
        } header: {
            Text(title)
        }
    }
}

/// Riga sfumata mostrata durante il primo caricamento, al posto della rotellina.
struct RigaSegnaposto: View {
    @State private var attenuata = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Caricamento del contenuto in corso").font(.subheadline.weight(.semibold))
            Text("Dettagli dell'elemento").font(.caption)
        }
        .redacted(reason: .placeholder)
        .opacity(attenuata ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: attenuata)
        .onAppear { attenuata = true }
        .accessibilityLabel("Caricamento")
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
                LuogoLezione(aula: lezione.aula, sede: lezione.sede)
                TimeStatusBadge(inizio: lezione.inizio, fine: lezione.fine, annullato: lezione.annullato, adesso: adesso)
                if lezione.modificataLocalmente {
                    Label("Modificata da te", systemImage: "pencil").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                }
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
    /// Etichetta corta per quando le pillole non ci stanno (es. "Secondo trimestre" → "2° trimestre").
    var titoloBreve: ((Item) -> String)? = nil
    let onSelect: (Item) -> Void

    var body: some View {
        // Centrate se ci stanno (anche in versione compatta, es. tre trimestri), altrimenti scorrevoli.
        ViewThatFits(in: .horizontal) {
            pillole(compatte: false).padding(.horizontal).frame(maxWidth: .infinity)
            pillole(compatte: true).padding(.horizontal).frame(maxWidth: .infinity)
            if titoloBreve != nil {
                pillole(compatte: true, brevi: true).padding(.horizontal).frame(maxWidth: .infinity)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                pillole(compatte: true, brevi: titoloBreve != nil).padding(.horizontal)
            }
        }
    }

    private func pillole(compatte: Bool, brevi: Bool = false) -> some View {
        HStack(spacing: compatte ? 6 : 8) {
            ForEach(items) { item in
                let on = item == selected
                Button { onSelect(item) } label: {
                    Text(brevi ? (titoloBreve?(item) ?? title(item)) : title(item))
                        .font((compatte ? Font.footnote : .subheadline).weight(on ? .semibold : .regular))
                        .padding(.horizontal, compatte ? 10 : 14).padding(.vertical, 7)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize()
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

/// Riga con icona a larghezza fissa, così le etichette restano allineate anche con simboli larghi.
struct RigaIcona: View {
    let titolo: String
    let simbolo: String
    init(_ titolo: String, simbolo: String) { self.titolo = titolo; self.simbolo = simbolo }

    var body: some View {
        Label {
            Text(titolo)
        } icon: {
            Image(systemName: simbolo).frame(width: 28)
        }
    }
}

/// Aula in evidenza e sede sulla riga sotto, invece di "Aula · Sede" che va a capo a metà.
struct LuogoLezione: View {
    let aula: String
    let sede: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "mappin.and.ellipse").font(.caption2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(aula).font(.caption.weight(.medium))
                if !sede.isEmpty { Text(sede).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Riga che scarica un PDF pubblico dell'Ateneo e lo apre con Quick Look, senza uscire dall'app.
struct DocumentoPDFRow: View {
    let titolo: String
    let simbolo: String
    let url: URL
    @Environment(AppModel.self) private var app
    @State private var anteprima: URL?
    @State private var inCorso = false
    @State private var errore: String?

    var body: some View {
        Button {
            Task {
                inCorso = true
                errore = nil
                defer { inCorso = false }
                do { anteprima = try await app.services.documenti.pdf(url) } catch { errore = app.message(error) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(titolo, systemImage: simbolo)
                    Spacer()
                    if inCorso { ProgressView() }
                }
                if let errore { Text(errore).font(.caption).foregroundStyle(.red) }
            }
        }
        .disabled(inCorso)
        .quickLookPreview($anteprima)
    }
}
