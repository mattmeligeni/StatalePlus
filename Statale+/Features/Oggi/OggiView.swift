import SwiftUI

/// Cruscotto: lezioni di oggi, prossimo appello prenotato, avvisi Ariel recenti, tasse.
struct OggiView: View {
    @Environment(AppModel.self) private var app
    @State private var avvisi = Live<[AvvisoAriel]>()
    @State private var tasse = Live<SituazioneTasse>()

    var body: some View {
        NavigationStack {
            List {
                header

                LiveSection(title: "Lezioni di oggi", live: app.lezioniUtente, retry: app.loadLezioniUtente) { lezioni in
                    let oggi = lezioni.filter { Formats.calendar.isDateInToday($0.inizio) }
                    if oggi.isEmpty {
                        Text("Nessuna lezione oggi").foregroundStyle(.secondary)
                    } else {
                        ForEach(oggi) { LezioneOggiRow(lezione: $0) }
                    }
                }

                LiveSection(title: "Prossimo appello prenotato", live: app.prenotazioni, retry: app.loadPrenotazioni) { _ in
                    if let next = app.prossimoAppelloPrenotato {
                        PrenotazioneRow(prenotazione: next.prenotazione, appello: next.appello)
                    } else {
                        Text("Nessun appello prenotato").foregroundStyle(.secondary)
                    }
                }

                LiveSection(title: "Avvisi Ariel (ultimi 7 giorni)", live: avvisi, retry: loadAvvisi) { list in
                    if list.isEmpty {
                        Text("Nessun avviso recente").foregroundStyle(.secondary)
                    } else {
                        ForEach(list) { a in
                            NavigationLink { DiscussionView(discussione: a.discussione) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.discussione.titolo).font(.subheadline.weight(.semibold))
                                    Text(a.corso).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    if let d = a.discussione.ultimaAttivita ?? a.discussione.creata {
                                        Text(d, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                LiveSection(title: "Tasse", live: tasse, retry: loadTasse) { t in
                    if t.totaleDaPagare > 0 {
                        Label("Da pagare: \(Formats.euroString(t.totaleDaPagare))", systemImage: "eurosign.circle")
                            .foregroundStyle(.red)
                    } else {
                        Label("Nessun importo da pagare", systemImage: "checkmark.seal").foregroundStyle(.green)
                    }
                    if let s = t.prossimaScadenza {
                        Label("Prossima scadenza: \(s.formatted(date: .long, time: .omitted))", systemImage: "calendar.badge.exclamationmark")
                    }
                }

                UpdatedFooter(date: app.lezioniUtente.updatedAt).listRowBackground(Color.clear)
            }
            .navigationTitle("Oggi")
            .refreshable { await loadAll() }
            .task {
                async let a: Void = app.lezioniUtente.updatedAt == nil ? app.loadLezioniUtente() : ()
                async let b: Void = app.prenotazioni.updatedAt == nil ? app.loadPrenotazioni() : ()
                async let c: Void = app.appelliUtente.updatedAt == nil ? app.loadAppelliUtente() : ()
                async let d: Void = avvisi.loadIfNeeded { try await fetchAvvisi() }
                async let e: Void = tasse.loadIfNeeded { try await app.services.unimia.tasse() }
                async let f: Void = app.slotPresenze.updatedAt == nil ? app.loadPresenze() : ()
                _ = await (a, b, c, d, e, f)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ProfileAvatar(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(saluto).font(.title2.bold())
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "it_IT"))).capitalized)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private var saluto: String {
        let nome = app.studente?.nome.split(separator: " ").first.map { $0.capitalized } ?? ""
        let h = Formats.calendar.component(.hour, from: .now)
        let s = h < 13 ? "Buongiorno" : h < 18 ? "Buon pomeriggio" : "Buonasera"
        return nome.isEmpty ? s : "\(s), \(nome)"
    }

    private func loadAll() async {
        app.segnaRefresh()
        async let p: Void = app.loadPresenze()
        async let a: Void = app.loadLezioniUtente()
        async let b: Void = app.loadPrenotazioni()
        async let c: Void = app.loadAppelliUtente()
        async let d: Void = loadAvvisi()
        async let e: Void = loadTasse()
        _ = await (p, a, b, c, d, e)
    }

    private func loadAvvisi() async { await avvisi.load { try await fetchAvvisi() } }
    private func loadTasse() async { await tasse.load { try await app.services.unimia.tasse() } }

    private func fetchAvvisi() async throws -> [AvvisoAriel] {
        let corsi: [InsegnamentoOfferta]
        if let cached = app.store.snapshot.offerta, !app.store.isStale(app.store.snapshot.offertaAggiornata, ttl: StableStore.ttlOfferta) {
            corsi = cached
        } else {
            corsi = try await app.services.ariel.offerta()
            app.store.update { $0.offerta = corsi; $0.offertaAggiornata = .now }
        }
        let since = Date.now.addingTimeInterval(-7 * 86_400)
        return await app.services.ariel.avvisiRecenti(corsi: corsi.filter(\.attivo), since: since)
            .map { AvvisoAriel(corso: $0.corso.titolo, discussione: $0.discussione) }
    }
}

/// Lezione di oggi con le azioni rapide, visibili da 10 minuti prima dell'inizio fino alla fine:
/// "Conferma presenza" sparisce quando la presenza risulta registrata (server, altro dispositivo o risposta positiva).
private struct LezioneOggiRow: View {
    let lezione: Lezione
    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                LezioneRow(lezione: lezione)
                if AppModel.inFinestraAzioni(lezione, now: ctx.date) {
                    HStack(spacing: 10) {
                        if app.presenzaConfermata(lezione) {
                            Label("Presenza registrata", systemImage: "checkmark.seal.fill")
                                .font(.caption.bold()).foregroundStyle(.green)
                        } else {
                            Button { app.apriConfermaPresenza(lezione) } label: {
                                Label("Conferma presenza", systemImage: "hand.raised.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                        Button { app.avviaRegistrazione(lezione) } label: {
                            Label(app.recorder.state == .idle ? "Inizia registrazione" : "Registrazione in corso",
                                  systemImage: app.recorder.state == .idle ? "record.circle" : "waveform")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .font(.caption.weight(.semibold))
                    .controlSize(.small)
                    .padding(.leading, 64)
                }
            }
        }
    }
}

struct AvvisoAriel: Identifiable {
    var id: String { discussione.id }
    let corso: String
    let discussione: DiscussioneForum
}

/// Appello prenotato su SIFA, con aula/sede dal calendario Agenda quando disponibili.
struct PrenotazioneRow: View {
    let prenotazione: Prenotazione
    let appello: Appello?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text((appello?.insegnamento ?? prenotazione.esame).capitalized(with: Locale(identifier: "it_IT")))
                .font(.subheadline.weight(.semibold))
            Text((appello?.inizio ?? prenotazione.data).formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "it_IT"))))
                .font(.caption)
            if let appello {
                HStack {
                    Label("\(appello.aula) · \(appello.sede)", systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    MapsButton(aula: appello.aula, sede: appello.sede, codici: appello.aulaCodici) { Text("Mappa") }
                        .font(.caption).buttonStyle(.borderless)
                }
            }
            TimeStatusBadge(inizio: appello?.inizio ?? prenotazione.data, fine: appello?.fine, annullato: appello?.annullato ?? false)
        }
    }
}

/// Appello del calendario Agenda.
struct AppelloRow: View {
    let appello: Appello

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(appello.insegnamento).font(.subheadline.weight(.semibold)).strikethrough(appello.annullato)
            Text(appello.inizio.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "it_IT"))))
                .font(.caption)
            HStack {
                Label("\(appello.aula) · \(appello.sede)", systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                MapsButton(aula: appello.aula, sede: appello.sede, codici: appello.aulaCodici) { Text("Mappa") }
                    .font(.caption).buttonStyle(.borderless)
            }
            if !appello.docenti.isEmpty {
                Text(appello.docenti.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
            }
            TimeStatusBadge(inizio: appello.inizio, fine: appello.fine, annullato: appello.annullato)
            if !appello.note.isEmpty { Text(appello.note).font(.caption).foregroundStyle(.orange) }
        }
    }
}
