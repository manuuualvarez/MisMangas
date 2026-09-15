//
//  MangaSynopsisView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// The synopsis; a long one starts folded behind "Read more".
struct MangaSynopsisView: View {
    let synopsis: String

    @State private var isExpanded = false

    /// Synopses longer than this many characters are folded.
    private static let foldThreshold = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitleView(title: "Synopsis")
            if synopsis.count > Self.foldThreshold {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Text(synopsis)
                        .padding(.top, 4)
                } label: {
                    Group {
                        if isExpanded {
                            Text("Read less")
                        } else {
                            Text("Read more")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            } else {
                Text(synopsis)
            }
        }
    }
}

#Preview("Short", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let synopsis = mangas.first?.synopsis { MangaSynopsisView(synopsis: synopsis).padding() }
}

#Preview("Folded", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    MangaSynopsisView(synopsis: mangas.compactMap(\.synopsis).joined(separator: " ")).padding()
}
