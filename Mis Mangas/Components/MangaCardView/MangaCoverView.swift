//
//  MangaCoverView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// A manga cover at one of three fixed sizes, with rounded corners.
struct MangaCoverView: View {
    enum Size {
        case small
        case medium
        case large

        var width: CGFloat {
            switch self {
            case .small: 80
            case .medium: 140
            case .large: 200
            }
        }

        var height: CGFloat {
            width * 1.5
        }
    }

    let manga: Manga
    var size: Size = .small

    var body: some View {
        RemoteImageView(url: manga.coverURL)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Medium", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first { MangaCoverView(manga: manga, size: .medium) }
}
