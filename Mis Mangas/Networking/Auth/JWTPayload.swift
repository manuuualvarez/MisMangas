//
//  JWTPayload.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// The claims of the session JWT the app reads locally. The signature is never verified on the
/// device: that is the server's job. `exp` arrives as seconds since 1970 with decimals.
struct JWTPayload: Codable {
    let exp: Date
    let email: String
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case exp
        case email
        case userID = "user_id"
    }
}

/// Reads the payload (second segment) of a JWT. Any token that is not three segments, whose
/// payload is not valid base64url or JSON, or that lacks `exp`, `email` or `user_id` throws
/// `AuthError.invalidToken`.
func decodeJWTPayload(_ token: String) throws(AuthError) -> JWTPayload {
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3, let data = Data(base64URLEncoded: String(segments[1])) else {
        throw .invalidToken
    }
    do {
        return try JSONDecoder.jwtPayload.decode(JWTPayload.self, from: data)
    } catch {
        throw .invalidToken
    }
}

private extension JSONDecoder {
    /// JWT claims carry dates as seconds since 1970 (with decimals), unlike the ISO 8601 dates of
    /// the API bodies decoded by `JSONDecoder.app`.
    static let jwtPayload: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
