//
//  Statale_App.swift
//  Statale+
//
//  Created by Mattia Meligeni on 29/09/2026.
//

import SwiftUI

@main
struct Statale_App: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .gestiTastiera()
                .environment(app)
                .environment(\.locale, Formats.it)
        }
    }
}
