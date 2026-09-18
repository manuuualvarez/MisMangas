//
//  MangaAuthorsView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// The credited authors, one per line with their role ("Akira Toriyama · Story & Art"). Each
/// one is a button: tapping it asks the screen that shows this detail to list the author's works.
struct MangaAuthorsView: View {
    let authors: [Author]
    @Environment(\.applyCatalogMode) private var applyCatalogMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionTitleView(title: "Authors")
            ForEach(authors) { author in
                Button {
                    applyCatalogMode?.apply(.byAuthor(id: author.id, name: author.fullName))
                } label: {
                    credit(of: author)
                        .multilineTextAlignment(.leading)
                        // A text line is shorter than a comfortable touch target, and a button
                        // label centers itself: keep the credit against the leading edge.
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    author.roleValue == .none
                        ? author.fullName
                        : String(localized: "\(author.fullName), \(author.roleValue.displayName)")
                )
                .accessibilityHint("Shows mangas by this author")
            }
            .font(.subheadline)
        }
    }

    private func credit(of author: Author) -> Text {
        if author.roleValue == .none {
            Text(author.fullName)
        } else {
            Text("\(author.fullName) · \(author.roleValue.displayName)")
        }
    }
}

#Preview("Authors", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first { MangaAuthorsView(authors: manga.authors).padding() }
}
