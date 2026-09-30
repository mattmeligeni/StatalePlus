import SwiftUI

/// Unica schermata di login: email @studenti.unimi.it (o solo "nome.cognome") + password → Keychain.
struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var mostraPassword = false

    private var esito: Result<String, Credentials.EmailError> { Credentials.normalizzaEmail(email) }
    private var emailValida: String? { if case .success(let e) = esito { e } else { nil } }
    private var valid: Bool { emailValida != nil && !password.isEmpty }

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
                    Label {
                        Text("L'accesso è riservato agli studenti immatricolati, in possesso di un indirizzo email **@\(Credentials.dominioStudenti)**.")
                    } icon: {
                        Image(systemName: "graduationcap.fill").foregroundStyle(Color.accentColor)
                    }
                    .font(.callout)
                }
                Section {
                    TextField("nome.cognome", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Group {
                            if mostraPassword {
                                TextField("Password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(.password)
                        Button { mostraPassword.toggle() } label: {
                            Image(systemName: mostraPassword ? "eye.slash" : "eye").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(mostraPassword ? "Nascondi password" : "Mostra password")
                    }
                } footer: {
                    emailFooter
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

    @ViewBuilder
    private var emailFooter: some View {
        switch esito {
        case .success(let e):
            Text("Accederai come \(e). Le credenziali restano nel Portachiavi di questo dispositivo.")
        case .failure(.vuota):
            Text("Puoi scrivere solo nome.cognome: il dominio @\(Credentials.dominioStudenti) viene aggiunto in automatico.")
        case .failure(let err):
            Label(err.errorDescription ?? "", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
