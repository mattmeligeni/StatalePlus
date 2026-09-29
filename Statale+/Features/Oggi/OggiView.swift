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
                    let futura = LezioniOggiList.prossimaNeiGiorniSuccessivi(lezioni)
                    if oggi.isEmpty {
                        Text("Nessuna lezione oggi").foregroundStyle(.secondary)
                        if let futura { ProssimaLezioneNota(lezione: futura, adesso: .now) }
                    } else {
                        LezioniOggiList(lezioni: oggi, prossimaFutura: futura)
                    }
                }

                LiveSection(title: "Prossimo appello prenotato", live: app.prenotazioni, retry: app.loadPrenotazioni) { _ in
                    if let next = app.prossimoAppelloPrenotato {
                        PrenotazioneRow(prenotazione: next.prenotazione, appello: next.appello)
                    } else {
                        Text("Nessun appello prenotato").foregroundStyle(.secondary)
                    }
                }

                LiveSection(title: "Avvisi Ariel (ultimi 10 giorni)", live: avvisi, retry: loadAvvisi) { list in
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
        let since = Date.now.addingTimeInterval(-10 * 86_400)
        return await app.services.ariel.avvisiRecenti(corsi: corsi.filter(\.attivo), since: since)
            .map { AvvisoAriel(corso: $0.corso.titolo, discussione: $0.discussione) }
    }
}

/// Lezioni di oggi, aggiornate dal vivo (ogni secondo per riga):
/// - la **prossima** lezione (prima non annullata non ancora finita, anche se in corso) è in grassetto;
/// - fra una lezione e l'altra (o prima della prima) la barra "Ora HH:MM" sta sopra la prossima lezione;
/// - durante una lezione, sul bordo sinistro della riga, una traccia verticale con un pallino che scorre in tempo reale
///   e pulsa (fermo con "Riduci movimento");
/// - a fine giornata "Lezioni finite per oggi" in fondo.
/// `oraSimulata` (solo per le preview) fa partire l'orologio da un'ora scelta, che poi avanza normalmente.
struct LezioniOggiList: View {
    let lezioni: [Lezione]
    var mostraAzioni = true
    /// Prima lezione dei giorni successivi: mostrata solo quando le lezioni di oggi sono finite.
    let prossimaFutura: Lezione?
    private let sfasamento: TimeInterval

    init(lezioni: [Lezione], prossimaFutura: Lezione? = nil, oraSimulata: Date? = nil, mostraAzioni: Bool = true) {
        self.lezioni = lezioni.sorted { $0.inizio < $1.inizio }
        self.prossimaFutura = prossimaFutura
        self.mostraAzioni = mostraAzioni
        sfasamento = oraSimulata?.timeIntervalSinceNow ?? 0
    }

    /// Prima lezione non annullata da domani in poi.
    static func prossimaNeiGiorniSuccessivi(_ tutte: [Lezione], oggi: Date = .now) -> Lezione? {
        let domani = Formats.calendar.date(byAdding: .day, value: 1, to: Formats.calendar.startOfDay(for: oggi)) ?? oggi
        return tutte.filter { !$0.annullato && $0.inizio >= domani }.min { $0.inizio < $1.inizio }
    }

    static func indiceProssima(_ lezioni: [Lezione], adesso: Date) -> Int? {
        lezioni.firstIndex { !$0.annullato && $0.fine > adesso }
    }

    static func inCorso(_ l: Lezione, _ adesso: Date) -> Bool { l.inizio <= adesso && adesso < l.fine }

    /// Frazione di lezione trascorsa (0…1).
    static func frazione(_ l: Lezione, _ adesso: Date) -> Double {
        let totale = l.fine.timeIntervalSince(l.inizio)
        return totale > 0 ? min(1, max(0, adesso.timeIntervalSince(l.inizio) / totale)) : 0
    }

    var body: some View {
        ForEach(Array(lezioni.enumerated()), id: \.element.id) { i, _ in
            LezioneOggiRow(lezioni: lezioni, indice: i, sfasamento: sfasamento, mostraAzioni: mostraAzioni,
                           prossimaFutura: prossimaFutura)
        }
    }
}

/// Indicatore dell'ora corrente fra le lezioni.
struct BarraOra: View {
    let adesso: Date
    var testo: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(testo ?? "Ora \(Formats.time(adesso))")
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(.red)
                .fixedSize()
            Circle().fill(.red).frame(width: 7, height: 7)
            Rectangle().fill(.red).frame(height: 1.5)
        }
        .accessibilityLabel(testo ?? "Ora \(Formats.time(adesso))")
    }
}

/// Nota "Prossima lezione" a lezioni del giorno terminate: giorno relativo, data, ora, materia e aula.
/// Un tap apre Orario sulla settimana della lezione, evidenziandola.
struct ProssimaLezioneNota: View {
    let lezione: Lezione
    let adesso: Date
    @Environment(AppModel.self) private var app

    private var quando: String {
        let cal = Formats.calendar
        let giorni = cal.dateComponents([.day], from: cal.startOfDay(for: adesso), to: cal.startOfDay(for: lezione.inizio)).day ?? 0
        let data = lezione.inizio.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "it_IT")))
        let relativo = giorni <= 0 ? "Oggi" : giorni == 1 ? "Domani" : "Tra \(giorni) giorni"
        return "\(relativo) · \(data), \(Formats.time(lezione.inizio))"
    }

    var body: some View {
        Button { app.mostraInOrario(lezione) } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prossima lezione").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Text(quando).font(.subheadline)
                    Text(lezione.insegnamento).font(.subheadline.weight(.semibold))
                    Label("\(lezione.aula) · \(lezione.sede)", systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Apre l'orario sulla settimana della lezione")
    }
}

/// Traccia verticale della lezione in corso: parte colorata fino al tempo trascorso, pallino che scorre dal vivo
/// con un alone pulsante e un bagliore che scende lungo la parte già trascorsa.
private struct AvanzamentoLezione: View {
    let lezione: Lezione
    let sfasamento: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: riduciMovimento)) { ctx in
            let t = ctx.date.addingTimeInterval(sfasamento)
            let frazione = LezioniOggiList.frazione(lezione, t)
            let secondi = ctx.date.timeIntervalSinceReferenceDate
            let battito = riduciMovimento ? 0 : (secondi.truncatingRemainder(dividingBy: 1.6)) / 1.6     // 0…1
            let scia = riduciMovimento ? -1 : (secondi.truncatingRemainder(dividingBy: 2.4)) / 2.4       // 0…1
            GeometryReader { g in
                let h = g.size.height
                let y = h * frazione
                ZStack(alignment: .top) {
                    Capsule().fill(Color.red.opacity(0.15)).frame(width: 3)
                    Capsule().fill(Color.red.opacity(0.85)).frame(width: 3, height: max(y, 3))
                    if scia >= 0, y > 12 {
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 3, height: 12)
                            .offset(y: (y - 12) * scia)
                    }
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.45 * (1 - battito)))
                            .frame(width: 10 + 14 * battito, height: 10 + 14 * battito)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
                    .frame(width: 24, height: 24)
                    .offset(y: min(max(y - 12, -7), h - 17))
                }
                .frame(width: 24)
            }
            .frame(width: 24)
            .accessibilityElement()
            .accessibilityLabel("Lezione in corso, \(Int(frazione * 100)) per cento trascorso")
        }
        .frame(width: 24)
        .padding(.vertical, 2)
    }
}

/// Lezione di oggi, ricalcolata ogni secondo. Azioni rapide da 10 minuti prima dell'inizio fino alla fine:
/// "Conferma presenza" sparisce quando la presenza risulta registrata (server, altro dispositivo o risposta positiva).
private struct LezioneOggiRow: View {
    let lezioni: [Lezione]
    let indice: Int
    let sfasamento: TimeInterval
    var mostraAzioni = true
    var prossimaFutura: Lezione?
    @Environment(AppModel.self) private var app

    private var lezione: Lezione { lezioni[indice] }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let t = ctx.date.addingTimeInterval(sfasamento)
            let prossima = LezioniOggiList.indiceProssima(lezioni, adesso: t)
            let eProssima = indice == prossima
            let inCorso = eProssima && LezioniOggiList.inCorso(lezione, t)
            let enfasi: LezioneRow.Enfasi = eProssima ? .prossima : (lezione.fine <= t ? .passata : .normale)
            VStack(alignment: .leading, spacing: 8) {
                if eProssima && !inCorso { BarraOra(adesso: t).transition(.opacity) }
                LezioneRow(lezione: lezione, enfasi: enfasi, adesso: t)
                    .overlay(alignment: .leading) {
                        if inCorso {
                            AvanzamentoLezione(lezione: lezione, sfasamento: sfasamento).offset(x: -20).transition(.opacity)
                        }
                    }
                if mostraAzioni, AppModel.inFinestraAzioni(lezione, now: t) {
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
                if prossima == nil, indice == lezioni.count - 1 {
                    BarraOra(adesso: t, testo: "Lezioni finite per oggi").transition(.opacity)
                    if let prossimaFutura { ProssimaLezioneNota(lezione: prossimaFutura, adesso: t).transition(.opacity) }
                }
            }
            .animation(.easeInOut(duration: 0.4), value: prossima)
            .animation(.easeInOut(duration: 0.4), value: inCorso)
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

#if DEBUG
// MARK: - Anteprima locale

extension Lezione {
    /// Lezione finta di oggi per le preview: orari "HH:mm".
    static func anteprima(_ inizio: String, _ fine: String, _ nome: String,
                          aula: String = "Aula 101", sede: String = "Festa del Perdono", annullata: Bool = false,
                          giorniDaOggi: Int = 0) -> Lezione {
        let oggi = Formats.calendar.date(byAdding: .day, value: giorniDaOggi, to: .now) ?? .now
        return Lezione(id: UUID().uuidString, codiceInsegnamento: "ABC-1", insegnamento: nome, docente: "Mario Bianchi",
                       inizio: Formats.at(oggi, inizio) ?? oggi, fine: Formats.at(oggi, fine) ?? oggi,
                       aula: aula, aulaCodice: "", sede: sede, annullato: annullata, tipo: "Lezione", note: "")
    }
}

/// Ora di oggi "HH:mm" (per simulare l'ora corrente nella preview).
private func oraDiOggi(_ hhmm: String) -> Date { Formats.at(.now, hhmm) ?? .now }

#Preview("Lezioni di oggi") {
    // Cambia gli orari e `adesso` (l'ora da cui parte l'orologio, che poi avanza dal vivo).
    let lezioni: [Lezione] = [
        .anteprima("08:30", "10:30", "Neuropsicologia clinica"),
        .anteprima("11:00", "13:00", "Psicometria", aula: "Aula 208"),
        .anteprima("14:30", "16:30", "Neuroscienze cognitive", aula: "Sala Conferenze", annullata: true),
        .anteprima("17:00", "18:30", "Laboratorio di valutazione", aula: "Aula K21", sede: "Noto"),
    ]
    // Prima lezione dei giorni successivi (es. lunedì se oggi è giovedì): compare a lezioni di oggi finite (es. "19:00").
    let prossima = Lezione.anteprima("09:30", "11:30", "Psicometria", aula: "Aula 208", giorniDaOggi: 4)
    let adesso = oraDiOggi("18:59")   // oppure: Date.now
    return List {
        Section("Lezioni di oggi") {
            LezioniOggiList(lezioni: lezioni, prossimaFutura: prossima, oraSimulata: adesso, mostraAzioni: false)
        }
    }
    .environment(AppModel())
}
#endif
