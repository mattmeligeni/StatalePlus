//
//  ContentView.swift
//  Statale+
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
        .onAppear { app.segnaRefresh(); app.avviaAutoRefresh() }
        .onDisappear { app.fermaAutoRefresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.avviaAutoRefresh() } else if phase == .background { app.fermaAutoRefresh() }
        }
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
