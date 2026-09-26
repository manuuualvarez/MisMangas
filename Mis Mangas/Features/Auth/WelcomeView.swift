//
//  WelcomeView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// The screen without a session: the app's claim, the way into an account (sign in or create
/// one) and the guest mode, which keeps the collection on the device. After a session ended on its
/// own, it says so. The actions stay pinned at the bottom; at accessibility text sizes they scroll
/// with the rest, since pinned they would leave no room for it.
struct WelcomeView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        // Decorative: at accessibility sizes the room goes to the text.
                        Image(systemName: "books.vertical")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                    Text("Mis Mangas")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Your manga collection, on this device and in the cloud.")
                        .font(.body)
                        .foregroundStyle(.mmSecondaryLabel)
                        .multilineTextAlignment(.center)
                    if let message = session.expiredMessage {
                        Label(message, systemImage: "clock.badge.exclamationmark")
                            .font(.callout)
                            .padding(.top, 8)
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        WelcomeActionsView()
                            .padding(.top)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Centers content that fits; content that does not starts at the top, title first.
            .defaultScrollAnchor(.center, for: .alignment)
            .safeAreaInset(edge: .bottom) {
                if !dynamicTypeSize.isAccessibilitySize {
                    WelcomeActionsView()
                        .frame(maxWidth: 480)
                        .padding()
                }
            }
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .signIn:
                    SignInView()
                case .signUp:
                    SignUpView()
                }
            }
        }
        .task(id: session.expiredMessage) {
            if let message = session.expiredMessage {
                // This screen has just replaced the tabs: a normal announcement would be cut short.
                var announcement = AttributedString(message)
                announcement.accessibilitySpeechAnnouncementPriority = .high
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
    }
}

#Preview("Welcome", traits: .sampleData) {
    WelcomeView()
}

#Preview("Session expired", traits: .sampleData) {
    @Previewable @Environment(SessionViewModel.self) var session
    WelcomeView()
        .task { await session.expire() }
}
