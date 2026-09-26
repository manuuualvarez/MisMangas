//
//  WatchPayloadTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// The dictionary form of the messages between the iPhone and the watch. The two apps update
/// separately, so the format is fixed: two keys, `type` and `payload` (the JSON of the message,
/// with dates as seconds since the reference date, fraction included). Oracle: values built here
/// and the JSON literals of the agreed format, copied verbatim below.
@Suite("WatchPayload")
struct WatchPayloadTests {
    // MARK: - Agreed format

    static let contractSnapshotJSON = """
    {
      "generatedAt": 810936000.25,
      "items": [
        { "mangaID": 42, "title": "Dragon Ball", "coverURL": "https://cdn.myanimelist.net/images/manga/1/267793l.jpg",
          "readingVolume": 7, "volumes": 42, "completeCollection": false, "updatedAt": 810935880.5 }
      ]
    }
    """

    static let contractUpdateJSON = """
    { "mangaID": 42, "readingVolume": 8, "sentAt": 810936060.125 }
    """

    /// The values the literal snapshot above stands for, written by hand.
    static let contractSnapshot = ReadingSnapshot(
        generatedAt: Date(timeIntervalSinceReferenceDate: 810_936_000.25),
        items: [
            ReadingItem(
                mangaID: 42,
                title: "Dragon Ball",
                coverURL: "https://cdn.myanimelist.net/images/manga/1/267793l.jpg",
                readingVolume: 7,
                volumes: 42,
                completeCollection: false,
                updatedAt: Date(timeIntervalSinceReferenceDate: 810_935_880.5)
            ),
        ]
    )

    /// The values the literal update above stands for, written by hand.
    static let contractUpdate = ReadingUpdate(
        mangaID: 42,
        readingVolume: 8,
        sentAt: Date(timeIntervalSinceReferenceDate: 810_936_060.125)
    )

    // MARK: - Round trip

    /// Dates with fractions below the millisecond: a format that rounds or truncates them would
    /// let an update look no later than the change it follows.
    static let roundTripPayloads: [WatchPayload] = [
        .readingSnapshot(ReadingSnapshot(
            generatedAt: Date(timeIntervalSinceReferenceDate: 810_936_000.25),
            items: [
                ReadingItem(
                    mangaID: 42,
                    title: "Dragon Ball",
                    coverURL: "https://cdn.myanimelist.net/images/manga/1/267793l.jpg",
                    readingVolume: 7,
                    volumes: 42,
                    completeCollection: false,
                    updatedAt: Date(timeIntervalSinceReferenceDate: 810_935_880.000123)
                ),
                ReadingItem(
                    mangaID: 1,
                    title: "Monster",
                    coverURL: nil,
                    readingVolume: nil,
                    volumes: nil,
                    completeCollection: true,
                    updatedAt: Date(timeIntervalSinceReferenceDate: 810_935_000.987654)
                ),
            ]
        )),
        .readingSnapshot(ReadingSnapshot(generatedAt: Date(timeIntervalSinceReferenceDate: 810_936_120.5), items: [])),
        .readingUpdate(ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: Date(timeIntervalSinceReferenceDate: 810_936_060.000456))),
    ]

    @Test(arguments: WatchPayloadTests.roundTripPayloads)
    func `A payload read back from its dictionary equals the original, dates to the fraction of a second`(payload: WatchPayload) throws {
        let decoded = try WatchPayload(dictionary: payload.dictionary())

        #expect(decoded == payload)
    }

    @Test(arguments: [
        (WatchPayload.readingSnapshot(WatchPayloadTests.contractSnapshot), "readingSnapshot"),
        (WatchPayload.readingUpdate(WatchPayloadTests.contractUpdate), "readingUpdate"),
    ])
    func `The dictionary has only the type of the message and its JSON as data`(payload: WatchPayload, type: String) throws {
        let dictionary = try payload.dictionary()

        #expect(Set(dictionary.keys) == ["type", "payload"])
        #expect(dictionary["type"] as? String == type)
        #expect(dictionary["payload"] is Data)
    }

    // MARK: - Format written

    /// The JSON an older app expects to read: these key names, dates as plain numbers.
    private struct UpdateWire: Decodable {
        let mangaID: Int
        let readingVolume: Int
        let sentAt: Double
    }

    private struct SnapshotWire: Decodable {
        struct Item: Decodable {
            let mangaID: Int
            let title: String
            let coverURL: String?
            let readingVolume: Int?
            let volumes: Int?
            let completeCollection: Bool
            let updatedAt: Double
        }

        let generatedAt: Double
        let items: [Item]
    }

    @Test
    func `A reading update is written with the agreed keys and its date as seconds with fraction`() throws {
        let dictionary = try WatchPayload.readingUpdate(Self.contractUpdate).dictionary()
        let data = try #require(dictionary["payload"] as? Data)

        let wire = try JSONDecoder().decode(UpdateWire.self, from: data)

        #expect(wire.mangaID == 42)
        #expect(wire.readingVolume == 8)
        #expect(wire.sentAt == 810_936_060.125)
    }

    @Test
    func `A reading snapshot is written with the agreed keys and its dates as seconds with fraction`() throws {
        let dictionary = try WatchPayload.readingSnapshot(Self.contractSnapshot).dictionary()
        let data = try #require(dictionary["payload"] as? Data)

        let wire = try JSONDecoder().decode(SnapshotWire.self, from: data)

        #expect(wire.generatedAt == 810_936_000.25)
        let item = try #require(wire.items.first)
        #expect(wire.items.count == 1)
        #expect(item.mangaID == 42)
        #expect(item.title == "Dragon Ball")
        #expect(item.coverURL == "https://cdn.myanimelist.net/images/manga/1/267793l.jpg")
        #expect(item.readingVolume == 7)
        #expect(item.volumes == 42)
        #expect(item.completeCollection == false)
        #expect(item.updatedAt == 810_935_880.5)
    }

    // MARK: - Format read

    @Test(arguments: [
        ("readingSnapshot", WatchPayloadTests.contractSnapshotJSON, WatchPayload.readingSnapshot(WatchPayloadTests.contractSnapshot)),
        ("readingUpdate", WatchPayloadTests.contractUpdateJSON, WatchPayload.readingUpdate(WatchPayloadTests.contractUpdate)),
    ])
    func `A dictionary in the agreed format decodes to the values it was written with`(type: String, json: String, expected: WatchPayload) throws {
        let dictionary: [String: Any] = ["type": type, "payload": Data(json.utf8)]

        let decoded = try WatchPayload(dictionary: dictionary)

        #expect(decoded == expected)
    }

    /// A dictionary that is not a message of this app: each case breaks one thing of an otherwise
    /// valid reading update.
    enum MalformedDictionary: CaseIterable, CustomTestStringConvertible {
        case unknownType
        case missingType
        case typeNotString
        case missingPayload
        case payloadNotData

        var dictionary: [String: Any] {
            let payload = Data(WatchPayloadTests.contractUpdateJSON.utf8)
            switch self {
            case .unknownType:
                return ["type": "somethingElse", "payload": payload]
            case .missingType:
                return ["payload": payload]
            case .typeNotString:
                return ["type": 42, "payload": payload]
            case .missingPayload:
                return ["type": "readingUpdate"]
            case .payloadNotData:
                return ["type": "readingUpdate", "payload": WatchPayloadTests.contractUpdateJSON]
            }
        }

        var testDescription: String {
            switch self {
            case .unknownType: "unknown type"
            case .missingType: "missing type"
            case .typeNotString: "type that is not a string"
            case .missingPayload: "missing payload"
            case .payloadNotData: "payload that is not data"
            }
        }
    }

    @Test(arguments: WatchPayloadTests.MalformedDictionary.allCases)
    func `A dictionary that is not a message of this app is unrecognized`(malformed: MalformedDictionary) {
        let dictionary = malformed.dictionary

        expectUnrecognizedPayload { try WatchPayload(dictionary: dictionary) }
    }

    @Test(arguments: [
        ("readingUpdate", "{}"),
        ("readingSnapshot", WatchPayloadTests.contractUpdateJSON),
        ("readingUpdate", WatchPayloadTests.contractSnapshotJSON),
        ("readingUpdate", "not json"),
    ])
    func `A known type whose JSON is not that message fails to decode`(type: String, json: String) {
        let dictionary: [String: Any] = ["type": type, "payload": Data(json.utf8)]

        expectDecodingError { try WatchPayload(dictionary: dictionary) }
    }

    // MARK: - Size

    /// A snapshot of `count` items at the upper end of real data: 200-character titles and
    /// cover URLs of about 120 characters.
    static func largeSnapshot(count: Int) -> ReadingSnapshot {
        let items = (0 ..< count).map { index in
            ReadingItem(
                mangaID: 100_000 + index,
                title: String(String(repeating: "Long manga title \(index) ", count: 20).prefix(200)),
                coverURL: "https://cdn.myanimelist.net/images/manga/\(index)/" + String(repeating: "c", count: 70) + "l.jpg",
                readingVolume: 123,
                volumes: 456,
                completeCollection: index.isMultiple(of: 2),
                updatedAt: Date(timeIntervalSinceReferenceDate: 810_936_000.125 + Double(index))
            )
        }
        return ReadingSnapshot(generatedAt: Date(timeIntervalSinceReferenceDate: 810_937_000.5), items: items)
    }

    @Test
    func `A snapshot of fifty long items is sent and read back unchanged`() throws {
        let payload = WatchPayload.readingSnapshot(Self.largeSnapshot(count: 50))

        let decoded = try WatchPayload(dictionary: payload.dictionary())

        #expect(decoded == payload)
    }

    @Test
    func `A snapshot whose JSON exceeds the size cap is too large to send`() throws {
        let snapshot = Self.largeSnapshot(count: 400)
        // Premise: the titles alone are 80,000 bytes, above the 60 KB cap.
        let encodedSize = try JSONEncoder().encode(snapshot).count
        try #require(encodedSize > WatchPayload.maximumEncodedSize)

        expectPayloadTooLarge { try WatchPayload.readingSnapshot(snapshot).dictionary() }
    }
}
