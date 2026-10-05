import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import PhotosUI

/// Contenitore per gli altri servizi. Il percorso è in `AppModel` per l'apertura diretta da Oggi (Presenze).
struct AltroView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.altroPath) {
            List {
                Section {
                    NavigationLink(value: AltroRoute.carriera) { Label("Carriera e libretto", systemImage: "graduationcap") }
                    NavigationLink(value: AltroRoute.tasse) { Label("Tasse e pagamenti", systemImage: "eurosign.circle") }
                    NavigationLink(value: AltroRoute.esami) { Label("Esami", systemImage: "pencil.and.list.clipboard") }
                    NavigationLink(value: AltroRoute.aule) { Label("Aule", systemImage: "building.2") }
                    NavigationLink(value: AltroRoute.presenze) { Label("Presenze", systemImage: "person.badge.clock") }
                    NavigationLink(value: AltroRoute.ia) { Label("IA", systemImage: "cpu") }
                    NavigationLink(value: AltroRoute.impostazioni) { Label("Impostazioni", systemImage: "gearshape") }
                }
                Section {
                    NavigationLink(value: AltroRoute.crediti) { Label("Crediti", systemImage: "heart.text.square") }
                } footer: {
                    Disclaimer().padding(.top, 20)
                }
            }
            .listSectionSpacing(32)
            .navigationTitle("Altro")
            .navigationDestination(for: AltroRoute.self) { route in
                switch route {
                case .carriera: CarrieraView()
                case .tasse: TasseView()
                case .esami: EsamiView()
                case .aule: AuleView()
                case .presenze: PresenzeView()
                case .ia: IAView()
                case .impostazioni: ImpostazioniView()
                case .crediti: CreditiView()
                }
            }
        }
    }
}

// MARK: - Carriera (UNIMIA)

struct CarrieraView: View {
    @Environment(AppModel.self) private var app
    @State private var recapiti = Live<Recapiti>()
    @State private var libretto = Live<Libretto>()
    @State private var esiti = Live<EsitiInAttesa>()

    var body: some View {
        List {
            if let s = app.studente {
                Section("Studente") {
                    LabeledContent("Nome", value: Testo.persona(s.nome))
                    LabeledContent("Matricola", value: s.matricola)
                    LabeledContent("Corso", value: Testo.nomeCorso(s.corso))
                    LabeledContent("Codice corso", value: s.codiceCorso)
                    LabeledContent("Tipo", value: Testo.frase(s.tipoCorso))
                    LabeledContent("Anno", value: "\(s.anno)°")
                    LabeledContent("Iscrizione", value: Testo.frase(s.statoIscrizione))
                    LabeledContent("Ultimo a.a.", value: s.ultimoAnnoIscrizione)
                }
            }
            LiveSection(title: "Recapiti", live: recapiti, retry: loadRecapiti) { r in
                LabeledContent("Residenza", value: Testo.indirizzo(r.residenza))
                LabeledContent("Recapito", value: Testo.indirizzo(r.recapito))
                LabeledContent("Cellulare", value: r.cellulare)
                LabeledContent("Email", value: r.email.lowercased())
            }
            LiveSection(title: "Libretto", live: libretto, retry: loadLibretto) { l in
                if l.vuoto {
                    Text("Non hai ancora sostenuto esami.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(l.righe.enumerated()), id: \.offset) { _, riga in
                        VStack(alignment: .leading) {
                            ForEach((l.colonne.isEmpty ? riga.keys.sorted() : l.colonne), id: \.self) { k in
                                if let v = riga[k], !v.isEmpty { LabeledContent(k, value: v).font(.caption) }
                            }
                        }
                    }
                }
            }
            LiveSection(title: "Esiti da accettare", live: esiti, retry: loadEsiti) { e in
                Label(e.inAttesa ? "Hai esiti in attesa di accettazione (entro 10 giorni)" : "Nessun esito in attesa",
                      systemImage: e.inAttesa ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(e.inAttesa ? .orange : .green)
            }
        }
        .navigationTitle("Carriera")
        .refreshable { await loadAll() }
        .task {
            async let a: Void = recapiti.loadIfNeeded { try await app.services.unimia.profilo().1 }
            async let b: Void = libretto.loadIfNeeded { try await libr() }
            async let c: Void = esiti.loadIfNeeded { try await app.services.unimia.esitiInAttesa() }
            _ = await (a, b, c)
        }
    }

    private func libr() async throws -> Libretto {
        guard let m = app.studente?.matricola else { throw NetError.unexpectedPage("profilo") }
        return try await app.services.unimia.libretto(matricola: m)
    }
    private func loadRecapiti() async { await recapiti.load { try await app.services.unimia.profilo().1 } }
    private func loadLibretto() async { await libretto.load { try await libr() } }
    private func loadEsiti() async { await esiti.load { try await app.services.unimia.esitiInAttesa() } }
    private func loadAll() async {
        async let a: Void = loadRecapiti(); async let b: Void = loadLibretto(); async let c: Void = loadEsiti()
        _ = await (a, b, c)
    }
}

// MARK: - Tasse (UNIMIA, solo lettura)

struct TasseView: View {
    @Environment(AppModel.self) private var app
    @State private var tasse = Live<SituazioneTasse>()

    var body: some View {
        List {
            LiveSection(title: "Anno accademico \(tasse.value?.annoAccademico.replacingOccurrences(of: " - ", with: "/") ?? "")", live: tasse, retry: load) { t in
                ForEach(t.righe) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Testo.voceTassa(r.causale)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Formats.euroString(r.dovuto)).font(.subheadline).monospacedDigit()
                        }
                        HStack(spacing: 4) {
                            if let d = r.dataPagamento {
                                Text("Rata \(r.rata) · pagata il \(d.formatted(.dateTime.day().month(.wide).year().locale(Formats.it)))")
                                Spacer()
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Text("Rata \(r.rata)")
                                Spacer()
                                if r.daPagare > 0 { Text("Da pagare \(Formats.euroString(r.daPagare))").foregroundStyle(.red) }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Totale dovuto", value: Formats.euroString(t.totaleDovuto))
                LabeledContent("Totale pagato", value: Formats.euroString(t.totalePagato))
                LabeledContent("Da pagare", value: Formats.euroString(t.totaleDaPagare)).bold()
            }
            if let s = tasse.value?.prossimaScadenza {
                Section("Prossima scadenza") {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.descrizione)
                            if let nota = s.nota { Text(nota).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }
            }
            if let msgs = tasse.value?.messaggi, !msgs.isEmpty {
                Section("Avvisi") { ForEach(msgs, id: \.self) { Text(Testo.tipografia($0)).font(.subheadline) } }
            }
            UpdatedFooter(date: tasse.updatedAt).listRowBackground(Color.clear)
        }
        .navigationTitle("Tasse e pagamenti")
        .refreshable { await load() }
        .task { await tasse.loadIfNeeded { try await app.services.unimia.tasse() } }
    }

    private func load() async { await tasse.load { try await app.services.unimia.tasse() } }
}

// MARK: - Impostazioni

private struct StatoSessione: View {
    let nome: String
    let attiva: Bool
    var body: some View {
        LabeledContent(nome) {
            HStack(spacing: 6) {
                Circle().fill(attiva ? Color.green : Color(.systemGray3)).frame(width: 8, height: 8)
                Text(attiva ? "Attiva" : "Non attiva")
            }
        }
    }
}

struct ImpostazioniView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmLogout = false
    @State private var refreshing = false
    @State private var refreshError: String?
    @State private var fotoItem: PhotosPickerItem?
    @AppStorage("sogliaFrequenzaManuale") private var sogliaManuale = 0

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    ProfileAvatar(size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        let etichetta = app.photo.image == nil ? "Aggiungi foto" : "Cambia foto"
                        PhotosPicker(etichetta, selection: $fotoItem, matching: .images)
                        if app.photo.image != nil {
                            Button("Rimuovi foto", role: .destructive) { app.photo.remove() }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            Section("Account") {
                if let s = app.studente { LabeledContent("Nome", value: Testo.persona(s.nome)) }
                LabeledContent("Email", value: app.email ?? "—")
                if let s = app.studente {
                    LabeledContent("Matricola", value: s.matricola.uppercased())
                    LabeledContent("Corso", value: "\(Testo.nomeCorso(s.corso)) (\(s.codiceCorso))")
                }
            }
            Section {
                Picker("Soglia di frequenza", selection: $sogliaManuale) {
                    Text(app.obbligoFrequenza.map { "Automatica (\($0.percentuale)%)" } ?? "Automatica").tag(0)
                    ForEach([30, 40, 50, 60, 66, 70, 75, 80], id: \.self) { Text("\($0)%").tag($0) }
                }
            } header: {
                Text("Presenze")
            } footer: {
                Text(app.obbligoFrequenza != nil
                     ? "In automatico vale la percentuale del manifesto degli studi del tuo corso. Scegline una se per un insegnamento vale una regola diversa."
                     : "In automatico vale la percentuale indicata dal sistema presenze, finché non si trova il manifesto degli studi del tuo corso.")
            }
            Section {
                StatoSessione(nome: "CAS (UNIMIA, SIFA)", attiva: CookieJar.has("CASTGC"))
                StatoSessione(nome: "Ariel", attiva: CookieJar.has("arielauth"))
                if let e = app.arielError { Text(e).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Sessioni")
            } footer: {
                Text("Una sessione non attiva si riapre da sola alla prossima richiesta.")
            }
            Section("Dati salvati") {
                if let d = app.store.snapshot.profiloAggiornato { LabeledContent("Profilo", value: d.italiano(date: .abbreviated, time: .shortened)) }
                if let d = app.agenda?.aggiornato { LabeledContent("Insegnamenti", value: d.italiano(date: .abbreviated, time: .shortened)) }
                if let d = app.store.snapshot.offertaAggiornata { LabeledContent("Corsi Ariel", value: d.italiano(date: .abbreviated, time: .shortened)) }
                LabeledContent("Registrazioni", value: "\(app.recordings.items.count) · \(ByteCountFormatter.string(fromByteCount: app.recordings.spazioOccupato, countStyle: .file))")
                Button {
                    refreshing = true
                    Task {
                        do { try await app.aggiornaProfilo(); refreshError = nil } catch { refreshError = app.message(error) }
                        refreshing = false
                    }
                } label: { HStack { Label("Aggiorna profilo e insegnamenti", systemImage: "arrow.clockwise"); Spacer(); if refreshing { ProgressView() } } }
                .disabled(refreshing)
                if let refreshError { Text(refreshError).font(.caption).foregroundStyle(.red) }
            }
            ArchivioSection()
            Section {
                Button("Esci", role: .destructive) { confirmLogout = true }
            } footer: {
                Text("Rimuove password, cookie di sessione e dati universitari salvati. Potrai scegliere se tenere registrazioni, foto e cache.")
            }
        }
        .navigationTitle("Impostazioni")
        .onChange(of: fotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { app.photo.set(data) }
                fotoItem = nil
            }
        }
        .confirmationDialog("Uscire da Statale+?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Mantieni registrazioni, foto e cache") { app.logout(eliminaDatiLocali: false) }
            Button("Elimina anche registrazioni, foto e cache", role: .destructive) { app.logout(eliminaDatiLocali: true) }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Credenziali e dati dell'account vengono sempre rimossi. Registrazioni (\(app.recordings.items.count)), foto profilo e file scaricati possono restare sul dispositivo per usarli con un altro profilo.")
        }
    }
}


/// Esporta tutte le registrazioni in un file da salvare in File o iCloud Drive, e le reimporta (per cambiare
/// iPhone o reinstallare l'app senza perderle).
private struct ArchivioSection: View {
    @Environment(AppModel.self) private var app
    @State private var archivio: URL?
    @State private var inCorso = false
    @State private var importa = false
    @State private var messaggio: String?

    var body: some View {
        Section {
            if let archivio {
                ShareLink(item: archivio) {
                    Label("Salva l'archivio (\(ByteCountFormatter.string(fromByteCount: dimensione(archivio), countStyle: .file)))",
                          systemImage: "square.and.arrow.up")
                }
            } else {
                Button { esporta() } label: {
                    HStack { Label("Esporta tutte le registrazioni", systemImage: "archivebox"); Spacer(); if inCorso { ProgressView() } }
                }
                .disabled(inCorso || app.recordings.items.isEmpty)
            }
            Button { importa = true } label: { Label("Importa da un archivio", systemImage: "tray.and.arrow.down") }
                .disabled(inCorso)
            if let messaggio { Text(messaggio).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Backup delle registrazioni")
        } footer: {
            Text("Un unico file con audio, trascrizioni, riassunti e note, da salvare in File o iCloud Drive. Serve prima di disinstallare l'app o per passare a un altro iPhone. Le registrazioni già presenti non vengono duplicate.")
        }
        .fileImporter(isPresented: $importa, allowedContentTypes: [UTType(filenameExtension: "aar") ?? .data, .data]) { r in
            guard case .success(let url) = r else { return }
            inCorso = true
            Task {
                do {
                    let n = try await ArchivioRegistrazioni.importa(url, in: app.recordings.folder)
                    app.recordings.riconcilia()
                    messaggio = n == 0 ? "Tutte le registrazioni dell'archivio erano già presenti." : "Importate \(n) registrazioni."
                } catch {
                    messaggio = app.message(error)
                }
                inCorso = false
            }
        }
    }

    private func esporta() {
        inCorso = true
        messaggio = nil
        Task {
            do { archivio = try await ArchivioRegistrazioni.esporta(da: app.recordings.folder) } catch { messaggio = app.message(error) }
            inCorso = false
        }
    }

    private func dimensione(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
