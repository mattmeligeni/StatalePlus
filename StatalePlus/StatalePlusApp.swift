//
//  StatalePlusApp.swift
//  Statale Plus
//
//  Created by Mattia Meligeni on 29/09/2026.
//

import SwiftUI

@main
struct StatalePlusApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .gestiTastiera()
                .environment(app)
                .environment(\.locale, Formats.it)
                .onOpenURL { app.importaArchivio($0) }
                .alert("Archivio delle registrazioni", isPresented: Binding(
                    get: { app.esitoImportazione != nil }, set: { if !$0 { app.esitoImportazione = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(app.esitoImportazione ?? "")
                }
        }
    }
}
