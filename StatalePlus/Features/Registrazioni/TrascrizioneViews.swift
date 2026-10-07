import SwiftUI

// MARK: - Sezioni nel dettaglio

/// Trascrizione con Speech: avvio, avanzamento, anteprima e accesso al testo completo.
struct TrascrizioneSection: View {
    let registrazione: Registrazione
    var player: AudioPlayer? = nil
    @Environment(AppModel.self) private var app
    @State private var anteprima: String?
    @State private var mostraMotori = false
    @State private var confermaDownload = false
    @AppStorage("motoreTrascrizione") private var motore = MotoreTrascrizione.apple.rawValue
    @AppStorage(Preferenze.chiaveAvvisoTrascrizione) private var avvisoNascosto = false

    var body: some View {
        let id = registrazione.id
        Section {
            if let s = app.elaborazioni.stato(.trascrizione, id) {
                StatoElaborazione(stato: s) { app.elaborazioni.annulla(.trascrizione, id) }
            } else if registrazione.trascrittaIl != nil {
                if let anteprima { Text(anteprima).font(.callout).lineLimit(4).foregroundStyle(.secondary) }
                NavigationLink { TrascrizioneView(id: id, player: player) } label: {
                    Label("Leggi e modifica la trascrizione", systemImage: "text.alignleft")
                }
                if mostraAvviso {
                    AvvisoModelloMigliore(
                        titolo: "Non ti convince la trascrizione?",
                        testo: "Prova il modello più preciso, soprattutto con termini tecnici e nomi: stessa velocità e privacy, sempre sul telefono. Poi rifai la trascrizione dal menu ⋯.",
                        gestore: app.parakeet,
                        scarica: { confermaDownload = true },
                        nascondi: { avvisoNascosto = true })
                }
            } else if let motivo = LimitiElaborazione.bloccoTrascrizione(registrazione) {
                Label(motivo, systemImage: "clock.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
            } else {
                Button { app.elaborazioni.trascrivi(registrazione, in: app.recordings) } label: {
                    Label("Trascrivi registrazione", systemImage: "waveform.badge.magnifyingglass")
                }
            }
            if let e = app.elaborazioni.errori[id], app.elaborazioni.stato(.trascrizione, id) == nil, registrazione.trascrittaIl == nil {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Trascrizione")
        } footer: {
            if registrazione.trascrittaIl == nil, LimitiElaborazione.bloccoTrascrizione(registrazione) == nil,
               app.elaborazioni.stato(.trascrizione, id) == nil {
                VStack(alignment: .leading, spacing: 6) {
                    if motore == MotoreTrascrizione.parakeet.rawValue, ParakeetLocale.installato {
                        Text("Trascrizione con Parakeet.")
                    } else {
                        Text("Riconoscimento vocale di Apple. Sono disponibili modelli più precisi.")
                    }
                    Button("Scegli il modello") { mostraMotori = true }
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $mostraMotori) {
            NavigationStack {
                ImpostazioniTrascrizioneView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { mostraMotori = false } } }
            }
        }
        .sheet(isPresented: $confermaDownload) {
            ConfermaDownloadParakeet(gestore: app.parakeet).presentationDetents([.large])
        }
        .task(id: registrazione.trascrittaIl) {
            anteprima = app.recordings.trascrizione(id).map { String($0.prefix(400)) }
        }
    }

    /// Trascrizione fatta con il modello di base di Apple e il modello più preciso non ancora scaricato.
    private var mostraAvviso: Bool {
        !avvisoNascosto && motore != MotoreTrascrizione.parakeet.rawValue && app.parakeet.stato != .installato
    }
}

/// Riassunto con Apple Intelligence (sul telefono o online) o con Qwen scaricato. Sugli iPhone senza Apple
/// Intelligence propone di scaricare Qwen.
struct RiassuntoSection: View {
    let registrazione: Registrazione
    var player: AudioPlayer? = nil
    @Environment(AppModel.self) private var app
    @State private var testo: String?
    @State private var trascrizione: String?
    @State private var confermaDownload = false
    @AppStorage("motoreRiassunto") private var scelto = MotoreRiassunto.cloud.rawValue
    @AppStorage(Preferenze.chiaveAvvisoRiassunto) private var avvisoNascosto = false

    /// Il motore che si userà (si ricalcola quando cambiano scelta o download di Qwen).
    private var motore: MotoreRiassunto? {
        _ = scelto
        _ = app.qwen.stato
        return MotoreRiassunto.disponibile
    }

    var body: some View {
        let id = registrazione.id
        let blocco = LimitiElaborazione.bloccoRiassunto(registrazione, trascrizione: trascrizione)
        Section {
            if motore != nil {
                if let s = app.elaborazioni.stato(.riassunto, id) {
                    StatoElaborazione(stato: s) { app.elaborazioni.annulla(.riassunto, id) }
                } else if registrazione.riassuntoIl != nil, let testo {
                    MarkdownTesto(markdown: testo).lineLimit(8)
                    NavigationLink { RiassuntoView(id: id, player: player) } label: { Label("Apri riassunto", systemImage: "doc.text.magnifyingglass") }
                    if mostraAvviso {
                        AvvisoModelloMigliore(
                            titolo: "Non ti convince il riassunto?",
                            testo: "Prova il modello più completo: appunti più spiegati, con punti chiave e domande, sempre sul telefono. Poi rigeneralo dal menu ⋯ del riassunto.",
                            gestore: app.qwen,
                            scarica: { confermaDownload = true },
                            nascondi: { avvisoNascosto = true })
                    }
                } else if let blocco {
                    Label(blocco, systemImage: "clock.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button { app.elaborazioni.riassumi(registrazione, in: app.recordings) } label: {
                        Label("Genera riassunto", systemImage: "sparkles")
                    }
                }
            } else {
                switch AppleIntelligence.stato {
                case .nonAttiva:
                    Label("Attiva Apple Intelligence in Impostazioni per generare i riassunti delle lezioni\(QwenLocale.supportato ? ", oppure scarica il modello per i riassunti" : "").",
                          systemImage: "apple.intelligence")
                        .font(.callout)
                case .inPreparazione:
                    Label("Apple Intelligence sta scaricando il modello. Riprova tra poco.", systemImage: "arrow.down.circle")
                        .font(.callout)
                case .nonSupportata, .disponibile:
                    if QwenLocale.supportato {
                        Text("Su questo iPhone i riassunti li scrive un modello da scaricare una volta sola: appunti, punti chiave e domande di ripasso, sempre sul telefono.")
                            .font(.callout)
                    }
                }
                if QwenLocale.supportato, AppleIntelligence.stato != .inPreparazione {
                    DownloadModello(gestore: app.qwen, etichetta: "Scarica il modello per i riassunti") { confermaDownload = true }
                }
            }
        } header: {
            Label("Riassunto", systemImage: "sparkles")
        } footer: {
            if let motore, registrazione.riassuntoIl == nil, blocco == nil, app.elaborazioni.stato(.riassunto, id) == nil {
                Text(motore == .qwen
                     ? "Con \(motore.nome), solo dal testo trascritto: riassunto, punti chiave e domande di ripasso. Lavora con l'app aperta: se esci si mette in pausa e riprende quando torni."
                     : "Con \(motore.nome), solo dal testo trascritto: riassunto, punti chiave e domande di ripasso.")
            }
            if let e = app.elaborazioni.errori[id], app.elaborazioni.stato(.riassunto, id) == nil, registrazione.trascrittaIl != nil {
                Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .sheet(isPresented: $confermaDownload) {
            ConfermaDownloadQwen(gestore: app.qwen).presentationDetents([.large])
        }
        .task(id: registrazione.riassuntoIl) { testo = app.recordings.riassunto(id) }
        .task(id: registrazione.trascrittaIl) { trascrizione = app.recordings.trascrizione(id) }
    }

    /// Riassunto fatto con Apple Intelligence sul telefono e Qwen non ancora scaricato.
    private var mostraAvviso: Bool {
        !avvisoNascosto && motore == .apple && QwenLocale.supportato && app.qwen.stato != .installato
    }
}

/// «Non ti convince?»: invito a provare il modello più preciso sotto una trascrizione o un riassunto fatti con il
/// modello di base, con download e «Non mostrare più».
private struct AvvisoModelloMigliore: View {
    let titolo: String
    let testo: String
    let gestore: GestoreModello
    let scarica: () -> Void
    let nascondi: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(titolo).font(.subheadline.weight(.semibold))
                    Text(testo).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            }
            DownloadModello(gestore: gestore, etichetta: "Scarica il modello", azione: scarica)
            if gestore.stato == .assente {
                Button("Non mostrare più", action: nascondi)
                    .font(.caption).foregroundStyle(.secondary).buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Pulsante per scaricare un modello, o il suo avanzamento mentre si scarica.
private struct DownloadModello: View {
    let gestore: GestoreModello
    let etichetta: String
    let azione: () -> Void

    var body: some View {
        switch gestore.stato {
        case .assente:
            Button(action: azione) {
                Label("\(etichetta) (\(gestore.modello.dimensioneMB) MB)", systemImage: "arrow.down.circle")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderless)
        case .download(let p):
            BarraDownload(avanzamento: p, totaleMB: gestore.modello.dimensioneMB)
        case .installato:
            Label("Modello scaricato", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
        }
        if let e = gestore.errore {
            Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
    }
}

private struct StatoElaborazione: View {
    let stato: ElaborazioniAudio.Stato
    let annulla: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: stato.progresso) {
                Text(stato.messaggio).font(.callout)
            } currentValueLabel: {
                Text(stato.progresso.formatted(.percent.precision(.fractionLength(0)))).font(.caption.monospacedDigit())
            }
            if !stato.inPausa {
                Text(nota).font(.caption).foregroundStyle(.secondary)
            }
            Button("Annulla", role: .destructive, action: annulla).font(.callout).buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var nota: String {
        if stato.motore == MotoreRiassunto.qwen.nome {
            return "Tieni l'app aperta: se esci il riassunto si mette in pausa e riprende quando torni."
        }
        if stato.motore == MotoreTrascrizione.parakeet.nome && !NotaBackground.neuralEngineInBackground {
            return "Parakeet lavora con l'app aperta: se esci si mette in pausa e riprende quando torni."
        }
        return NotaBackground.testo
    }
}

// MARK: - Trascrizione completa

/// Trascrizione completa. In lettura segue l'audio: il paragrafo in ascolto è evidenziato (con la frase in corso),
/// la vista scorre da sola finché non la si scorre a mano («Segui l'audio» per tornare), un tocco su un paragrafo fa
/// partire l'audio da lì e la barra a destra mostra dove si è nel testo. La posizione viene dalle àncore salvate
/// durante la trascrizione (`MappaTesto`); per le trascrizioni senza àncore è stimata in proporzione alla durata.
/// Segnalibri a due vie: quelli presi durante la registrazione (o nel player) compaiono nel testo nel punto in cui
/// sono stati presi, elencati dietro il pulsante in alto; tenendo premuto un paragrafo se ne aggiunge uno, che vale
/// anche per l'audio (stesso elenco `Registrazione.segnalibri`, in secondi).
/// «Modifica» passa al testo modificabile, con Writing Tools.
struct TrascrizioneView: View {
    let id: UUID
    var player: AudioPlayer? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var testo = ""
    @State private var caricato = false
    @State private var modifica = false
    @State private var paragrafi: [ParagrafoConPosizione] = []
    @State private var mappa: MappaTesto?
    @State private var segui = true
    @State private var confermaRifai = false
    @State private var confermaElimina = false
    @State private var mostraSegnalibri = false
    /// Paragrafo a cui scorrere (scelto dall'elenco dei segnalibri).
    @State private var vaiAlParagrafo: Int?

    private var segnalibri: [TimeInterval] { app.recordings.item(id)?.segnalibri ?? [] }

    var body: some View {
        Group {
            if modifica {
                TextEditor(text: $testo)
                    .font(.body)
                    .strumentiScrittura()
                    .padding(.horizontal, 8)
                    .tastieraConChiudi()
            } else {
                lettura
            }
        }
        .navigationTitle("Trascrizione")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { player?.utilizzatori += 1 }
        .onDisappear { player?.utilizzatori -= 1 }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let player { MiniPlayer(player: player) }
                Text("\(testo.split(whereSeparator: \.isWhitespace).count) parole")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(6)
            }
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(modifica ? "Fine" : "Modifica") {
                    if modifica { salva() }
                    modifica.toggle()
                }
            }
            if !modifica {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mostraSegnalibri = true } label: {
                        Image(systemName: segnalibri.isEmpty ? "bookmark" : "bookmark.fill")
                    }
                    .accessibilityLabel("Segnalibri")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { ShareLink(item: testo) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { UIPasteboard.general.string = testo } label: { Label("Copia tutto", systemImage: "doc.on.doc") }
                    Button { confermaRifai = true } label: { Label("Trascrivi di nuovo", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { confermaElimina = true } label: { Label("Elimina trascrizione", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear {
            guard !caricato else { return }
            testo = app.recordings.trascrizione(id) ?? ""
            caricato = true
        }
        .task(id: testo) {
            // Paragrafi e mappa dei tempi si ricalcolano dopo le modifiche, con il salvataggio (debounce).
            guard caricato else { return }
            paragrafi = ParagrafoConPosizione.dividi(testo)
            let ancore = app.recordings.tempi(id)
            let durata = player?.duration ?? app.recordings.item(id)?.durata ?? 0
            let t = testo
            mappa = await Task.detached { MappaTesto(testo: t, ancore: ancore, durata: durata) }.value
            try? await Task.sleep(for: .seconds(1))
            salva()
        }
        .onDisappear { salva() }
        .sheet(isPresented: $mostraSegnalibri) {
            ElencoSegnalibri(segnalibri: segnalibri, estratto: estratto(al:), puòAggiungere: (player?.currentTime ?? 0) > 0,
                             aggiungiQui: { if let t = player?.currentTime { aggiungiSegnalibro(t) } },
                             vai: { t in
                                 mostraSegnalibri = false
                                 vaiA(tempo: t)
                             },
                             elimina: rimuoviSegnalibri)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Trascrivere di nuovo?", isPresented: $confermaRifai, titleVisibility: .visible) {
            Button("Trascrivi di nuovo", role: .destructive) {
                caricato = false
                app.recordings.salvaTrascrizione(id, nil)
                if let r = app.recordings.item(id) { app.elaborazioni.trascrivi(r, in: app.recordings) }
                dismiss()
            }
        } message: { Text("Le modifiche fatte a mano andranno perse.") }
        .confirmationDialog("Eliminare la trascrizione?", isPresented: $confermaElimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                caricato = false
                app.recordings.salvaTrascrizione(id, nil)
                dismiss()
            }
        }
    }

    // MARK: Lettura

    /// Posizione nel testo di ciò che si sta ascoltando (nil se l'audio non è partito).
    private var posizione: Int? {
        guard let player, let mappa, player.isPlaying || player.currentTime > 0 else { return nil }
        return mappa.posizione(al: player.currentTime)
    }

    private var lettura: some View {
        let posizione = posizione
        let attivo = posizione.flatMap { p in paragrafi.lastIndex { $0.inizio <= p } }
        let segni = segniPerParagrafo
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(paragrafi.indices, id: \.self) { i in
                        let p = paragrafi[i]
                        ParagrafoTrascrizione(testo: p.testo, evidenziato: i == attivo ? posizione.map { $0 - p.inizio } : nil,
                                              segnalibri: segni[i] ?? [])
                            .id(i)
                            .contentShape(Rectangle())
                            .onTapGesture { ascolta(da: p.inizio) }
                            .contextMenu {
                                Button { ascolta(da: p.inizio) } label: { Label("Ascolta da qui", systemImage: "play") }
                                Button { aggiungiSegnalibro(da: p.inizio) } label: { Label("Aggiungi segnalibro", systemImage: "bookmark") }
                                if let qui = segni[i], !qui.isEmpty {
                                    Button(role: .destructive) { rimuoviSegnalibri(qui.map(\.indice)) } label: {
                                        Label(qui.count == 1 ? "Togli il segnalibro" : "Togli i segnalibri", systemImage: "bookmark.slash")
                                    }
                                }
                                Button { UIPasteboard.general.string = p.testo } label: { Label("Copia paragrafo", systemImage: "doc.on.doc") }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .padding(.trailing, 8)
            }
            .onChange(of: vaiAlParagrafo) { _, nuovo in
                guard let nuovo else { return }
                withAnimation { proxy.scrollTo(nuovo, anchor: .center) }
                vaiAlParagrafo = nil
            }
            .onScrollPhaseChange { _, fase in
                if fase == .interacting, posizione != nil { segui = false }
            }
            .onChange(of: attivo) { _, nuovo in
                guard segui, let nuovo else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(nuovo, anchor: .center) }
            }
            .overlay(alignment: .trailing) {
                if let posizione, let mappa, mappa.lunghezza > 0 {
                    IndicatorePosizione(frazione: Double(posizione) / Double(mappa.lunghezza)) { f in
                        ascolta(da: Int(f * Double(mappa.lunghezza)))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !segui, let attivo {
                    Button {
                        segui = true
                        withAnimation { proxy.scrollTo(attivo, anchor: .center) }
                    } label: {
                        Label("Segui l'audio", systemImage: "waveform").font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    // MARK: Segnalibri

    /// Segnalibri di ogni paragrafo: numero (da 1, nell'ordine dell'audio), indice nell'elenco e posizione nel
    /// paragrafo della parola in cui sono stati presi.
    private var segniPerParagrafo: [Int: [SegnoNelTesto]] {
        guard let mappa, !paragrafi.isEmpty else { return [:] }
        var risultato: [Int: [SegnoNelTesto]] = [:]
        for (i, t) in segnalibri.enumerated() {
            guard let pos = mappa.posizione(al: t), let par = paragrafi.lastIndex(where: { $0.inizio <= pos }) else { continue }
            risultato[par, default: []].append(SegnoNelTesto(numero: i + 1, indice: i, posizione: pos - paragrafi[par].inizio))
        }
        return risultato
    }

    /// La frase della trascrizione dove cade un segnalibro (per l'elenco).
    private func estratto(al t: TimeInterval) -> String? {
        guard let pos = mappa?.posizione(al: t), let par = paragrafi.last(where: { $0.inizio <= pos }) else { return nil }
        let testo = par.testo
        let indice = testo.index(testo.startIndex, offsetBy: min(max(pos - par.inizio, 0), testo.count))
        var frase: String?
        testo.enumerateSubstrings(in: testo.startIndex..., options: .bySentences) { f, intervallo, _, stop in
            if intervallo.contains(indice) || intervallo.upperBound == indice { frase = f; stop = true }
        }
        return (frase ?? testo).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Segnalibro all'inizio di un paragrafo (tenuto premuto): vale anche per l'audio.
    private func aggiungiSegnalibro(da offset: Int) {
        guard let t = mappa?.tempo(per: offset) else { return }
        aggiungiSegnalibro(t)
    }

    private func aggiungiSegnalibro(_ t: TimeInterval) {
        guard var r = app.recordings.item(id), !r.segnalibri.contains(where: { abs($0 - t) < 1 }) else { return }
        r.segnalibri.append(max(0, t))
        r.segnalibri.sort()
        app.recordings.update(r)
    }

    private func rimuoviSegnalibri(_ indici: [Int]) {
        guard var r = app.recordings.item(id) else { return }
        r.segnalibri = r.segnalibri.enumerated().filter { !indici.contains($0.offset) }.map(\.element)
        app.recordings.update(r)
    }

    /// Dall'elenco: scorre al punto del testo e fa partire l'audio da lì.
    private func vaiA(tempo t: TimeInterval) {
        if let pos = mappa?.posizione(al: t), let par = paragrafi.lastIndex(where: { $0.inizio <= pos }) {
            vaiAlParagrafo = par
        }
        guard let player else { return }
        player.seek(to: max(0, t - 0.5))
        if !player.isPlaying { player.play() }
        segui = true
    }

    /// Fa partire l'audio dal punto del testo toccato e riprende a seguirlo.
    private func ascolta(da offset: Int) {
        guard let player, let t = mappa?.tempo(per: offset) else { return }
        player.seek(to: max(0, t - 0.5))
        if !player.isPlaying { player.play() }
        segui = true
    }

    private func salva() {
        guard caricato, testo != app.recordings.trascrizione(id) else { return }
        app.recordings.salvaTrascrizione(id, testo)
    }
}

/// Un paragrafo della trascrizione con la sua posizione (in caratteri) nel testo completo.
struct ParagrafoConPosizione: Sendable {
    let inizio: Int
    let testo: String

    /// Paragrafi separati da righe vuote (o da a capo, se il testo è stato modificato a mano).
    static func dividi(_ testo: String) -> [ParagrafoConPosizione] {
        var risultato: [ParagrafoConPosizione] = []
        var offset = 0
        for riga in testo.split(separator: "\n", omittingEmptySubsequences: false) {
            if !riga.trimmingCharacters(in: .whitespaces).isEmpty {
                risultato.append(ParagrafoConPosizione(inizio: offset, testo: String(riga)))
            }
            offset += riga.count + 1
        }
        return risultato
    }
}

/// Un segnalibro nel testo: numero mostrato, indice in `Registrazione.segnalibri`, posizione nel paragrafo.
private struct SegnoNelTesto: Equatable {
    let numero: Int
    let indice: Int
    let posizione: Int
}

/// Un paragrafo; se è quello in ascolto ha una barra colorata a sinistra e la frase in corso evidenziata. I segnalibri
/// sono un'icona arancione nel punto in cui sono stati presi.
private struct ParagrafoTrascrizione: View {
    let testo: String
    /// Posizione (in caratteri, nel paragrafo) della parola in ascolto.
    let evidenziato: Int?
    var segnalibri: [SegnoNelTesto] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(evidenziato != nil ? Color.accentColor : .clear)
                .frame(width: 3)
            conSegnalibri
                .font(.body)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeInOut(duration: 0.2), value: evidenziato != nil)
        .accessibilityHint(segnalibri.isEmpty ? "" : segnalibri.count == 1 ? "Contiene un segnalibro" : "Contiene \(segnalibri.count) segnalibri")
    }

    /// Il testo con le icone dei segnalibri inserite prima della parola in cui cadono.
    private var conSegnalibri: Text {
        let a = attribuito
        guard !segnalibri.isEmpty else { return Text(a) }
        var risultato = Text("")
        var inizio = a.startIndex
        for s in segnalibri.sorted(by: { $0.posizione < $1.posizione }) {
            let offset = min(max(s.posizione, 0), testo.count)
            let fine = a.characters.index(a.startIndex, offsetBy: offset)
            guard fine >= inizio else { continue }
            let segno = Text("\(Image(systemName: "bookmark.fill"))\(s.numero) ").font(.caption.bold()).foregroundStyle(.orange)
            risultato = Text("\(risultato)\(Text(AttributedString(a[inizio..<fine])))\(segno)")
            inizio = fine
        }
        return Text("\(risultato)\(Text(AttributedString(a[inizio...])))")
    }

    private var attribuito: AttributedString {
        var a = AttributedString(testo)
        guard let evidenziato else { return a }
        a.foregroundColor = .secondary
        let posizione = testo.index(testo.startIndex, offsetBy: min(max(evidenziato, 0), testo.count))
        var frase: Range<String.Index>?
        testo.enumerateSubstrings(in: testo.startIndex..., options: .bySentences) { _, intervallo, _, stop in
            if intervallo.contains(posizione) || intervallo.upperBound == posizione { frase = intervallo; stop = true }
        }
        if let frase, let r = Range(frase, in: a) {
            a[r].foregroundColor = .primary
            a[r].backgroundColor = Color.accentColor.opacity(0.18)
        }
        return a
    }
}

/// Elenco dei segnalibri della registrazione, con la frase della trascrizione in cui cadono: un tocco porta lì nel
/// testo e nell'audio.
private struct ElencoSegnalibri: View {
    let segnalibri: [TimeInterval]
    let estratto: (TimeInterval) -> String?
    let puòAggiungere: Bool
    let aggiungiQui: () -> Void
    let vai: (TimeInterval) -> Void
    let elimina: ([Int]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if segnalibri.isEmpty {
                    ContentUnavailableView("Nessun segnalibro", systemImage: "bookmark",
                                           description: Text("Aggiungili durante la registrazione, oppure tieni premuto un paragrafo della trascrizione."))
                }
                ForEach(Array(segnalibri.enumerated()), id: \.offset) { i, t in
                    Button { vai(t) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Segnalibro \(i + 1) · \(tempo(t))", systemImage: "bookmark.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            if let e = estratto(t) {
                                Text(e).font(.callout).foregroundStyle(.primary).lineLimit(3)
                            }
                        }
                    }
                }
                .onDelete { elimina(Array($0)) }
                if puòAggiungere {
                    Section {
                        Button { aggiungiQui() } label: { Label("Aggiungi al punto in ascolto", systemImage: "bookmark.circle") }
                    }
                }
            }
            .navigationTitle("Segnalibri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
    }

    private func tempo(_ t: TimeInterval) -> String {
        let s = Int(max(t, 0))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Barra sottile a destra del testo con il punto in ascolto; si tocca o trascina per spostarsi nell'audio.
private struct IndicatorePosizione: View {
    let frazione: Double
    let vai: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let altezza = geo.size.height
            ZStack(alignment: .top) {
                Capsule().fill(Color.secondary.opacity(0.2)).frame(width: 3)
                Capsule().fill(Color.accentColor)
                    .frame(width: 5, height: 22)
                    .offset(y: min(max(frazione * altezza - 11, 0), max(altezza - 22, 0)))
            }
            .frame(width: 20, height: altezza)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                vai(min(max(v.location.y / max(altezza, 1), 0), 1))
            })
        }
        .frame(width: 20)
        .padding(.vertical, 12)
        .padding(.trailing, 2)
        .accessibilityLabel("Posizione nel testo")
        .accessibilityValue("\(Int(frazione * 100)) per cento")
    }
}

// MARK: - Riassunto completo

struct RiassuntoView: View {
    let id: UUID
    var player: AudioPlayer? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var testo = ""
    @State private var caricato = false
    @State private var modifica = false
    @State private var pdf: URL?

    var body: some View {
        Group {
            if modifica {
                TextEditor(text: $testo)
                    .font(.body.monospaced())
                    .strumentiScrittura()
                    .padding(.horizontal, 8)
                    .tastieraConChiudi()
            } else {
                ScrollView {
                    MarkdownTesto(markdown: testo)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let player { MiniPlayer(player: player).background(.bar) }
        }
        .navigationTitle("Riassunto")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { player?.utilizzatori += 1 }
        .onDisappear { player?.utilizzatori -= 1 }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(modifica ? "Fine" : "Modifica") {
                    if modifica { salva() }
                    modifica.toggle()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let pdf {
                        ShareLink(item: pdf) { Label("Condividi o stampa il PDF", systemImage: "printer") }
                    }
                    Button { UIPasteboard.general.string = testo } label: { Label("Copia il testo", systemImage: "doc.on.doc") }
                    Button {
                        if let r = app.recordings.item(id) { app.elaborazioni.riassumi(r, in: app.recordings) }
                        dismiss()
                    } label: { Label("Genera di nuovo", systemImage: "sparkles") }
                    Button(role: .destructive) {
                        caricato = false
                        app.recordings.salvaRiassunto(id, nil)
                        dismiss()
                    } label: { Label("Elimina riassunto", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear {
            guard !caricato else { return }
            testo = app.recordings.riassunto(id) ?? ""
            caricato = true
        }
        .task(id: modifica ? "" : testo) {
            // PDF rigenerato quando il testo cambia (non durante la modifica).
            guard !modifica, !testo.isEmpty, let r = app.recordings.item(id) else { return }
            pdf = PDFRiassunto.crea(markdown: testo, titolo: r.titolo,
                                    sottotitolo: [r.insegnamento, r.creata.italiano(date: .long, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
        }
        .onDisappear { salva() }
    }

    private func salva() {
        guard caricato, testo != app.recordings.riassunto(id) else { return }
        app.recordings.salvaRiassunto(id, testo)
    }
}

// MARK: - Supporto

/// Rendering essenziale del Markdown dei riassunti: titoli `##`, elenchi puntati/numerati, grassetto/corsivo inline.
struct MarkdownTesto: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, riga in
                let r = riga.trimmingCharacters(in: .whitespaces)
                if r.hasPrefix("###") {
                    Text(inline(r.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                        .font(.subheadline.weight(.semibold)).padding(.top, 4)
                } else if r.hasPrefix("#") {
                    Text(inline(r.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                        .font(.title3.bold()).padding(.top, 10)
                } else if r.hasPrefix("- ") || r.hasPrefix("* ") || r.hasPrefix("• ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(String(r.dropFirst(2))))
                    }
                } else if let m = r.firstMatch(#"^(\d+)[.)]\s+(.*)$"#, group: 2), let n = r.firstMatch(#"^(\d+)[.)]"#) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n).").monospacedDigit()
                        Text(inline(m))
                    }
                } else if !r.isEmpty {
                    Text(inline(r))
                }
            }
        }
        .font(.callout)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

extension View {
    /// Writing Tools completi (riscrittura, correzione, riassunto).
    func strumentiScrittura() -> some View {
        writingToolsBehavior(.complete)
    }
}

/// Controlli essenziali dell'audio della registrazione mentre si legge trascrizione o riassunto (l'audio non si
/// ferma aprendo queste schermate). Compare solo se l'audio è stato avviato.
private struct MiniPlayer: View {
    let player: AudioPlayer
    /// Valore del cursore mentre lo si trascina: l'audio salta lì quando lo si lascia.
    @State private var trascinamento: Double?

    var body: some View {
        if player.duration > 0 {
            VStack(spacing: 2) {
                Slider(value: Binding(get: { trascinamento ?? player.currentTime }, set: { trascinamento = $0 }),
                       in: 0...max(player.duration, 1)) { inCorso in
                    if !inCorso, let t = trascinamento {
                        player.seek(to: t)
                        trascinamento = nil
                    }
                }
                .accessibilityLabel("Posizione nell'audio")
                HStack(spacing: 8) {
                    Button { player.skip(-15) } label: { Image(systemName: "gobackward.15").font(.title2).frame(width: 44, height: 44) }
                        .accessibilityLabel("Indietro di 15 secondi")
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title).frame(width: 52, height: 44)
                    }
                    .accessibilityLabel(player.isPlaying ? "Pausa" : "Riproduci")
                    Button { player.skip(30) } label: { Image(systemName: "goforward.30").font(.title2).frame(width: 44, height: 44) }
                        .accessibilityLabel("Avanti di 30 secondi")
                    Spacer(minLength: 4)
                    Text("\(durata(trascinamento ?? player.currentTime)) / \(durata(player.duration))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Menu {
                        Picker("Velocità", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                            ForEach(AudioPlayer.velocità, id: \.self) { Text(AudioPlayer.etichetta($0)).tag($0) }
                        }
                    } label: {
                        Text(AudioPlayer.etichetta(player.rate))
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 10).frame(minWidth: 52, minHeight: 32)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    .accessibilityLabel("Velocità di riproduzione")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityElement(children: .contain)
        }
    }

    private func durata(_ t: TimeInterval) -> String {
        let s = Int(max(t, 0))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
