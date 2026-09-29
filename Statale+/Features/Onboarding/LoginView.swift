import SwiftUI

/// Unica schermata di login: email @studenti.unimi.it + password → Keychain.
struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var email = ""
    @State private var password = ""
    @State private var working = false

    private var valid: Bool { email.contains("@") && email.lowercased().hasSuffix("unimi.it") && !password.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Statale+").font(.largeTitle.bold())
                        Text("UNIMIA, SIFA, Ariel e Agenda in un'unica app, con le credenziali di Ateneo.")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("nome.cognome@studenti.unimi.it", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Le credenziali restano nel Portachiavi di questo dispositivo.")
                }
                if let error = app.bootstrapError {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                Section {
                    Button {
                        working = true
                        Task { await app.login(email: email, password: password); working = false; password = "" }
                    } label: {
                        HStack { Spacer(); if working { ProgressView() } else { Text("Accedi").bold() }; Spacer() }
                    }
                    .disabled(!valid || working)
                }
            }
        }
    }
}
