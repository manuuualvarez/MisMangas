//
//  WatchPayload.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// A message between the iPhone and the watch, and its dictionary form: the only shape the
/// connectivity session transports. The dictionary holds the kind of message under `type` and
/// its JSON under `payload`; both apps are updated separately, so these keys never change.
enum WatchPayload: Hashable {
    case readingSnapshot(ReadingSnapshot)
    case readingUpdate(ReadingUpdate)

    /// Internal cap on the encoded JSON, in bytes; the system does not document its own limit.
    static let maximumEncodedSize = 60 * 1024

    private static let typeKey = "type"
    private static let payloadKey = "payload"
    /// Default date strategy on both sides: dates travel as seconds with their fraction, so the
    /// moment of a change survives the trip exactly and can be compared with another one.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private enum Kind: String {
        case readingSnapshot
        case readingUpdate
    }

    private var kind: Kind {
        switch self {
        case .readingSnapshot: .readingSnapshot
        case .readingUpdate: .readingUpdate
        }
    }

    func dictionary() throws(WatchTransportError) -> [String: Any] {
        let payload: Data
        do {
            payload = switch self {
            case let .readingSnapshot(snapshot): try Self.encoder.encode(snapshot)
            case let .readingUpdate(update): try Self.encoder.encode(update)
            }
        } catch {
            throw .encoding(error)
        }
        guard payload.count <= Self.maximumEncodedSize else {
            throw .payloadTooLarge
        }
        return [Self.typeKey: kind.rawValue, Self.payloadKey: payload]
    }

    init(dictionary: [String: Any]) throws(WatchTransportError) {
        guard let rawKind = dictionary[Self.typeKey] as? String,
              let kind = Kind(rawValue: rawKind),
              let payload = dictionary[Self.payloadKey] as? Data
        else {
            throw .unrecognizedPayload
        }
        do {
            switch kind {
            case .readingSnapshot:
                self = try .readingSnapshot(Self.decoder.decode(ReadingSnapshot.self, from: payload))
            case .readingUpdate:
                self = try .readingUpdate(Self.decoder.decode(ReadingUpdate.self, from: payload))
            }
        } catch {
            throw .decoding(error)
        }
    }
}
