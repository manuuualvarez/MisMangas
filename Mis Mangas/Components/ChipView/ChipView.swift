//
//  ChipView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// A read-only capsule for a genre, theme or demographic name.
struct ChipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }
}

#Preview("Genres", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    HStack { ForEach(mangas.first?.genres ?? [], id: \.self) { ChipView(text: $0) } }
}
