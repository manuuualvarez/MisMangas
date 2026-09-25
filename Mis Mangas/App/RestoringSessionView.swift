//
//  RestoringSessionView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// What the launch shows while it decides whether the session of an earlier launch resumes: no
/// screen of its own yet, only a sign that the app is loading.
struct RestoringSessionView: View {
    var body: some View {
        ProgressView()
            .accessibilityLabel("Loading")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.mmBackground)
    }
}

#Preview(traits: .sampleData) {
    RestoringSessionView()
}
