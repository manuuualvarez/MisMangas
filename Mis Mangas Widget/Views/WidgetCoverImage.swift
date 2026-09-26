//
//  WidgetCoverImage.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import ImageIO
import SwiftUI
import WidgetKit

/// A manga's cover as the app cached it, filling the space it is given and clipped to the
/// widget's corners; a book symbol when the file is missing or unreadable. Never downloads.
struct WidgetCoverImage: View {
    /// The cached cover; `nil` while the app has not written it.
    let fileURL: URL?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.clear
            .overlay {
                if let cover = Self.cover(at: fileURL) {
                    // A cover is media content: in accented mode it keeps its colors instead of
                    // turning into a white silhouette.
                    Image(decorative: cover, scale: displayScale)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.fill.secondary)
                        .overlay {
                            Image(systemName: "book.closed")
                                .imageScale(.large)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityHidden(true)
                }
            }
            .clipShape(ContainerRelativeShape())
    }

    private static func cover(at fileURL: URL?) -> CGImage? {
        guard let fileURL, let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

#Preview("Not cached yet") {
    WidgetCoverImage(fileURL: nil)
        .frame(width: 40, height: 56)
}
