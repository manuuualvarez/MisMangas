//
//  CollectionDTOTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// The collection contract of `/collection/manga`: the response entries decoded from a fixture
/// shaped like the OpenAPI `UserMangaCollectionDTO`, and the request body compared key by key
/// with literal JSON written from the OpenAPI `UserMangaCollectionRequest`, never with the
/// output of the app's own encoder.
@Suite("Collection DTOs")
struct CollectionDTOTests {
    /// A JSON value of the request body, so two bodies can be compared as key → value maps
    /// regardless of key order or whitespace.
    private enum WireValue: Decodable, Equatable {
        case null
        case bool(Bool)
        case integer(Int)
        case integers([Int])

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int.self) {
                self = .integer(value)
            } else {
                self = try .integers(container.decode([Int].self))
            }
        }
    }

    /// The top-level members of a JSON object. An explicit `null` and an absent key both mean
    /// "no value" to the server, so nulls are dropped before comparing.
    private static func wireObject(_ data: Data) throws -> [String: WireValue] {
        try JSONDecoder.app.decode([String: WireValue].self, from: data).filter { $0.value != .null }
    }

    private static func wireObject(_ json: String) throws -> [String: WireValue] {
        try wireObject(Data(json.utf8))
    }

    // MARK: - Response

    @Test func `The collection response decodes each entry with its full nested manga`() throws {
        let entries = try JSONDecoder.app.decode([UserMangaCollectionDTO].self, from: TestFixtures.data("collection_response.json"))

        #expect(entries.count == 2)
        let monster = try #require(entries.first)
        let expectedID = try #require(UUID(uuidString: "7C1E2A54-3B9D-4F6A-9E21-5D8C0B4F7A13"))
        #expect(monster.id == expectedID)
        #expect(monster.manga.id == 1)
        #expect(monster.manga.title == "Monster")
        #expect(monster.manga.synopsis?.hasPrefix("Kenzou Tenma, a renowned Japanese neurosurgeon") == true)
        #expect(monster.manga.authors.map(\.lastName) == ["Urasawa"])
        #expect(monster.volumesOwned == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18])
        #expect(monster.readingVolume == 12)
        #expect(monster.completeCollection)
    }

    @Test func `A null reading volume in the collection response decodes as nil`() throws {
        let entries = try JSONDecoder.app.decode([UserMangaCollectionDTO].self, from: TestFixtures.data("collection_response.json"))

        let berserk = try #require(entries.last)
        let expectedID = try #require(UUID(uuidString: "B2F4D6E8-1A3C-4E5F-8B7D-9C0E2F4A6B81"))
        #expect(berserk.id == expectedID)
        #expect(berserk.manga.id == 2)
        #expect(berserk.manga.title == "Berserk")
        #expect(berserk.volumesOwned == [1, 2, 3])
        #expect(berserk.readingVolume == nil)
        #expect(!berserk.completeCollection)
    }

    // MARK: - Request

    @Test func `A request encodes with exactly the keys and values of the contract`() throws {
        let request = UserMangaCollectionRequest(manga: 42, completeCollection: false, volumesOwned: [1, 2, 3], readingVolume: 2)

        let encoded = try Self.wireObject(JSONEncoder.app.encode(request))

        let contract = try Self.wireObject(#"{ "manga": 42, "completeCollection": false, "volumesOwned": [1, 2, 3], "readingVolume": 2 }"#)
        #expect(encoded == contract)
    }

    @Test func `A request without a reading volume sends none and decodes back unchanged`() throws {
        let request = UserMangaCollectionRequest(manga: 42, completeCollection: true, volumesOwned: [1, 2, 3], readingVolume: nil)

        let data = try JSONEncoder.app.encode(request)

        let contract = try Self.wireObject(#"{ "manga": 42, "completeCollection": true, "volumesOwned": [1, 2, 3] }"#)
        #expect(try Self.wireObject(data) == contract)
        let decoded = try JSONDecoder.app.decode(UserMangaCollectionRequest.self, from: data)
        #expect(decoded == request)
        #expect(decoded.readingVolume == nil)
    }
}
