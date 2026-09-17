//
//  DetailSectionTitleView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftUI

/// Small uppercase heading of a section of the detail screen, exposed as a header to VoiceOver.
struct DetailSectionTitleView: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.mmSecondaryLabel)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Title", traits: .sampleData) {
    DetailSectionTitleView(title: "Authors")
}
