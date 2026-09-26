//
//  MangaDeepLink.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// A link to a manga's detail, `mismangas://manga/{id}`: the widget builds it and the app reads it.
struct MangaDeepLink: Hashable {
    let mangaID: Int

    init(mangaID: Int) {
        self.mangaID = mangaID
    }

    /// Reads a link; `nil` for anything that is not exactly a manga link with a positive id written
    /// in digits alone (no sign, no leading zero, no escapes) and without user, password or port.
    /// The scheme is compared without case; a query or a fragment is ignored.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host() == Self.host,
              url.user == nil, url.password == nil, url.port == nil
        else {
            return nil
        }
        // The path as written, escapes included: "/42" and nothing else.
        let path = url.path(percentEncoded: true)
        guard path.first == "/" else {
            return nil
        }
        let id = path.dropFirst()
        guard id.wholeMatch(of: /[1-9][0-9]*/) != nil, let mangaID = Int(id) else {
            return nil
        }
        self.mangaID = mangaID
    }

    /// The link, ready for `widgetURL` or `Link`.
    var url: URL {
        Self.base.appending(path: String(mangaID), directoryHint: .notDirectory)
    }

    private static let scheme = "mismangas"
    private static let host = "manga"

    private static let base: URL = {
        guard let url = URL(string: "\(scheme)://\(host)") else {
            preconditionFailure("Invalid deep link base literal")
        }
        return url
    }()
}
