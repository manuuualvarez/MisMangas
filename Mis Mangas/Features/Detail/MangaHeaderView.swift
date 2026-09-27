//
//  MangaHeaderView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// Top of the detail: large cover, titles, score and publication line ("Finished · 1984–1995";
/// the range stays open, "1989–", while the manga has no end date). Read as one element.
struct MangaHeaderView: View {
    let manga: Manga

    var body: some View {
        VStack(spacing: 12) {
            // The title that follows names the manga; the cover's own label would only repeat it.
            MangaCoverView(manga: manga, size: .large)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(manga.title)
                    .font(.title2.bold())
                if let english = manga.titleEnglish, english != manga.title {
                    Text(english)
                        .font(.subheadline)
                        .foregroundStyle(.mmSecondaryLabel)
                }
                if let japanese = manga.attributedJapaneseTitle {
                    Text(japanese)
                        .font(.subheadline)
                        .foregroundStyle(.mmSecondaryLabel)
                }
                Label(manga.formattedScore, systemImage: "star.fill")
                    .font(.headline)
                    .accessibilityLabel(manga.scoreAccessibilityLabel)
                publication
                    .font(.subheadline)
                    .foregroundStyle(.mmSecondaryLabel)
                    .accessibilityLabel(manga.publicationAccessibilityLabel)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var publication: Text {
        let status = Text(manga.statusValue.displayName)
        guard let start = manga.startDate else {
            return status
        }
        let startYear = Text(start, format: .dateTime.year())
        if let end = manga.endDate {
            let endYear = Text(end, format: .dateTime.year())
            return Text("\(status) · \(startYear)–\(endYear)")
        }
        return Text("\(status) · \(startYear)–")
    }
}

#Preview("Header", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first { MangaHeaderView(manga: manga).padding() }
}
