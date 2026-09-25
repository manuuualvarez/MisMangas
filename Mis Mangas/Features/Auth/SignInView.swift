//
//  SignInView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// Sign in with an existing account. The button waits for a valid address and a password; the
/// server's answer (wrong credentials, no connection) shows under the fields, and the form stays.
/// While the server answers, the form cannot be left, so the attempt never outlives the screen.
struct SignInView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Email") {
                    TextField("Email", text: $email, prompt: Text(verbatim: "name@example.com"))
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
                }
                LabeledContent("Password") {
                    SecureField("Password", text: $password, prompt: Text("Required"))
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit(submit)
                }
            } footer: {
                if let message = session.failureMessage {
                    Text(message)
                        .foregroundStyle(.mmWarning)
                }
            }
            Section {
                Button(action: submit) {
                    ZStack {
                        // The title keeps its place while the spinner shows, so the row never
                        // changes height.
                        Text("Sign In")
                            .opacity(session.isAuthenticating ? 0 : 1)
                        if session.isAuthenticating {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!canSubmit)
                .accessibilityLabel(session.isAuthenticating ? Text("Signing in") : Text("Sign In"))
                .accessibilityHint(canSubmit ? Text(verbatim: "") : Text(Self.missingInput))
            }
        }
        .navigationTitle("Sign In")
        .navigationBarBackButtonHidden(session.isAuthenticating)
        .onAppear {
            session.clearFailure()
            focusedField = .email
        }
        .onChange(of: session.failureMessage) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private static let missingInput = String(localized: "Enter a valid email and your password")

    private var canSubmit: Bool {
        SessionViewModel.canSubmitSignIn(email: email, password: password) && !session.isAuthenticating
    }

    private func submit() {
        guard canSubmit else {
            // The keyboard's Go key reaches here with the form incomplete: say why nothing happens.
            if !session.isAuthenticating {
                AccessibilityNotification.Announcement(Self.missingInput).post()
            }
            return
        }
        Task {
            await session.signIn(email: email, password: password)
        }
    }
}

#Preview("Sign In", traits: .sampleData) {
    NavigationStack {
        SignInView()
    }
}

#Preview("Wrong credentials", traits: .sampleData(security: .fails(.invalidCredentials))) {
    @Previewable @Environment(SessionViewModel.self) var session
    NavigationStack {
        SignInView()
    }
    .task { await session.signIn(email: "reader@example.com", password: String(repeating: "x", count: 8)) }
}

#Preview("Signing in", traits: .sampleData(security: .waits)) {
    @Previewable @Environment(SessionViewModel.self) var session
    NavigationStack {
        SignInView()
    }
    .task { await session.signIn(email: "reader@example.com", password: String(repeating: "x", count: 8)) }
}
