//
//  JSONDecoder+App.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

extension JSONDecoder {
    /// Shared decoder for every API response. Dates are ISO 8601 (`1984-11-20T00:00:00Z`);
    /// the backend emits them without fractional seconds, but both forms are accepted.
    static let app: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            // Two accepted shapes with an explicit fallback; a failure on both is a real decoding error.
            if let date = try? Date.ISO8601FormatStyle().parse(raw) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date, got \"\(raw)\""
            )
        }
        return decoder
    }()
}
