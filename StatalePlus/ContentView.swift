//
//  ContentView.swift
//  Statale Plus
//
//  Created by Mattia Meligeni on 29/09/2026.
//

import SwiftUI

/// Radice: onboarding una tantum, poi TabView ottimizzata per l'uso live.
struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.phase {
            case .launching:
                ProgressView()
            case .onboarding:
                LoginView()
            case .bootstrapping(let step):
                BootstrapView(step: step)
            case .ready:
                MainTabView()
            }
        }
        .task { await app.start() }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            OggiView()
                .tabItem { Label("Oggi", systemImage: "sun.max") }
                .tag(AppTab.oggi)
            OrarioView()
                .tabItem { Label("Orario", systemImage: "calendar") }
                .tag(AppTab.orario)
            ArielCoursesView()
                .tabItem { Label("Ariel", systemImage: "books.vertical") }
                .tag(AppTab.ariel)
            RegistrazioniView()
                .tabItem { Label("Registrazioni", systemImage: "waveform") }
                .tag(AppTab.registrazioni)
            AltroView()
                .tabItem { Label("Altro", systemImage: "square.grid.2x2") }
                .tag(AppTab.altro)
        }
        .alert(titoloRecuperate, isPresented: Binding(
            get: { !app.recordings.recuperate.isEmpty && !app.avvisoRecuperateMostrato },
            set: { if !$0 { app.avvisoRecuperateMostrato = true } })) {
            Button("Controlla ora") {
                app.avvisoRecuperateMostrato = true
                app.tab = .registrazioni
                app.mostraRecuperate = true
            }
            Button("Più tardi", role: .cancel) { app.avvisoRecuperateMostrato = true }
        } message: {
            Text(messaggioRecuperate)
        }
        .onAppear { app.segnaRefresh(); app.avviaAutoRefresh() }
        .onDisappear { app.fermaAutoRefresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.avviaAutoRefresh() } else if phase == .background { app.fermaAutoRefresh() }
        }
    }
}

extension MainTabView {
    private var titoloRecuperate: String {
        app.recordings.recuperate.count == 1 ? "Registrazione recuperata" : "\(app.recordings.recuperate.count) registrazioni recuperate"
    }

    private var messaggioRecuperate: String {
        let una = app.recordings.recuperate.count == 1
        let daVerificare = app.recordings.recuperate.filter { app.recordings.item($0)?.richiedeVerifica == true }.count
        if daVerificare == 0 {
            return una ? "Una registrazione non era nell'elenco: è stata ripristinata dai suoi dati salvati."
                       : "Alcune registrazioni non erano nell'elenco: sono state ripristinate dai loro dati salvati."
        }
        return (una ? "Una registrazione non era nell'elenco ed è stata ripristinata in automatico"
                    : "Alcune registrazioni non erano nell'elenco e sono state ripristinate in automatico")
            + ": data, ora e insegnamento sono stati ricavati dal file e dall'orario. Puoi controllarli ora o più tardi da Registrazioni › Da verificare."
    }
}

private struct BootstrapView: View {
    let step: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(step).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
    }
}
