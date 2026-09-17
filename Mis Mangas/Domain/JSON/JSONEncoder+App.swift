//
//  JSONEncoder+App.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

extension JSONEncoder {
    /// Shared encoder for every request body. Symmetric with `JSONDecoder.app`.
    static let app: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
