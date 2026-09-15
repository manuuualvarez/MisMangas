//
//  MangaAuthorsView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// The credited authors, one per line with their role ("Akira Toriyama · Story & Art").
struct MangaAuthorsView: View {
    let authors: [Author]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailSectionTitleView(title: "Authors")
            ForEach(authors) { author in
                if author.roleValue == .none {
                    Text(author.fullName)
                } else {
                    Text("\(author.fullName) · \(author.roleValue.displayName)")
                        .accessibilityLabel(String(localized: "\(author.fullName), \(author.roleValue.displayName)"))
                }
            }
            .font(.subheadline)
        }
    }
}

#Preview("Authors", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first { MangaAuthorsView(authors: manga.authors).padding() }
}
