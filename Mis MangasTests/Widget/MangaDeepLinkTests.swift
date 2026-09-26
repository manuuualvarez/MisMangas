//
//  MangaDeepLinkTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// The `mismangas://manga/{id}` link read and built by `MangaDeepLink`. The oracle is the URL
/// scheme contract: the literal URLs below and the id each one must (or must not) yield.
@Suite("MangaDeepLink")
struct MangaDeepLinkTests {
    /// The canonical link, which every rejection below is measured against: a parser that accepts
    /// it and still refuses a near miss is rejecting it, not failing to parse at all.
    private static let canonical = "mismangas://manga/42"

    @Test(arguments: [
        "mismangas://manga/42",
        "MISMANGAS://manga/42",
        "mismangas://manga/42?src=widget",
    ])
    func `A manga link yields its id, whatever the case of the scheme and ignoring the query`(_ text: String) throws {
        let url = try #require(URL(string: text))

        #expect(MangaDeepLink(url: url)?.mangaID == 42)
    }

    @Test(arguments: [
        "mismangas://manga/",
        "mismangas://manga/abc",
        "mismangas://manga/0",
        "mismangas://manga/-3",
        "mismangas://author/1",
        "https://example.com/manga/42",
        "mismangas://manga/42/extra",
        "mismangas://manga/+42",
        "mismangas://manga/042",
        "mismangas://manga/%2B42",
        "mismangas://user@manga/42",
        "mismangas://user:pw@manga/42",
        "mismangas://manga:99/42",
    ])
    func `Anything that is not exactly a manga link with a positive id is rejected`(_ text: String) throws {
        let canonical = try #require(URL(string: Self.canonical))
        try #require(MangaDeepLink(url: canonical)?.mangaID == 42)
        let url = try #require(URL(string: text))

        #expect(MangaDeepLink(url: url) == nil)
    }

    @Test
    func `A built link is exactly the manga link and reads back as the same id`() {
        let url = MangaDeepLink(mangaID: 42).url

        #expect(url.absoluteString == "mismangas://manga/42")
        #expect(MangaDeepLink(url: url)?.mangaID == 42)
    }
}
