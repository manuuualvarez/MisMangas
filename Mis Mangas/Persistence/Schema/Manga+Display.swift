//
//  Manga+Display.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Presentation helpers of the stored model. Views read these instead of parsing raw fields.
extension Manga {
    var statusValue: MangaStatus {
        MangaStatus(rawValue: status) ?? .none
    }

    var coverURL: URL? {
        mainPictureURL.flatMap(URL.init(string:))
    }

    /// "First Last" of the first author, skipping empty name parts; `nil` without authors.
    var primaryAuthorName: String? {
        authors.first.map { author in
            [author.firstName, author.lastName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
}
