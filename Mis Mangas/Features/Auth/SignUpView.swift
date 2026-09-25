//
//  SignUpView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// Create an account, then sign in with it. The address is judged once the field is left, and the
/// button waits for it and for a confirmation that matches; a short password is refused on submit,
/// before any request. Each problem shows under the field it concerns. While the server answers,
/// the form cannot be left, so the attempt never outlives the screen.
struct SignUpView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    /// Set once the focus leaves the email field, so a half-typed address is not an error yet.
    @State private var isEmailTouched = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
        case confirmation
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
            } footer: {
                if let message = emailMessage {
                    Text(message)
                        .foregroundStyle(.mmWarning)
                }
            }
            Section {
                LabeledContent("Password") {
                    SecureField("Password", text: $password, prompt: Text("Required"))
                        .textContentType(.newPassword)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .password)
                        .onSubmit { focusedField = .confirmation }
                }
                LabeledContent("Confirm") {
                    SecureField("Confirm password", text: $confirmation, prompt: Text("Required"))
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .confirmation)
                        .onSubmit(submit)
                }
            } footer: {
                if let message = passwordMessage {
                    Text(message)
                        .foregroundStyle(.mmWarning)
                } else {
                    Text("At least 8 characters.")
                }
            }
            Section {
                Button(action: submit) {
                    ZStack {
                        // The title keeps its place while the spinner shows, so the row never
                        // changes height.
                        Text("Create Account")
                            .opacity(session.isAuthenticating ? 0 : 1)
                        if session.isAuthenticating {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!canSubmit)
                .accessibilityLabel(session.isAuthenticating ? Text("Creating account") : Text("Create Account"))
                .accessibilityHint(canSubmit ? Text(verbatim: "") : Text(Self.missingInput))
            }
        }
        .navigationTitle("Create Account")
        .navigationBarBackButtonHidden(session.isAuthenticating)
        .onAppear {
            session.clearFailure()
            focusedField = .email
        }
        .onChange(of: focusedField) { previous, _ in
            if previous == .email {
                isEmailTouched = true
            }
        }
        .onChange(of: emailMessage) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: passwordMessage) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private static let missingInput = String(localized: "Enter a valid email and a password, twice")

    /// The address problem once the field was left, or the server's answer about it.
    private var emailMessage: String? {
        let issue = isEmailTouched ? SessionViewModel.emailIssue(email) : nil
        return issue?.localizedDescription ?? session.emailFailureMessage
    }

    /// A confirmation that differs, or the answer to the last attempt about anything else.
    private var passwordMessage: String? {
        SessionViewModel.confirmationIssue(password: password, confirmation: confirmation) ?? session.passwordFailureMessage
    }

    private var canSubmit: Bool {
        SessionViewModel.canSubmitSignUp(email: email, password: password, confirmation: confirmation) && !session.isAuthenticating
    }

    private func submit() {
        guard canSubmit else {
            // The keyboard's Go key reaches here with the form incomplete: say why nothing happens.
            if !session.isAuthenticating {
                AccessibilityNotification.Announcement(passwordMessage ?? Self.missingInput).post()
            }
            return
        }
        Task {
            await session.signUp(email: email, password: password)
        }
    }
}

#Preview("Create Account", traits: .sampleData) {
    NavigationStack {
        SignUpView()
    }
}

#Preview("Email already registered", traits: .sampleData(security: .fails(.emailAlreadyRegistered))) {
    @Previewable @Environment(SessionViewModel.self) var session
    NavigationStack {
        SignUpView()
    }
    .task { await session.signUp(email: "reader@example.com", password: String(repeating: "x", count: 8)) }
}
