//
//  SessionTestTokenFactory.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// Synthetic JWTs with the shape the backend emits (`header.payload.signature`, base64url
/// without padding) and the payload verified against the live API:
/// `{ exp, iat, email, user_id, sub: "saotome-manga" }`, with `exp`/`iat` in seconds since 1970
/// carrying decimals. The signature is dummy bytes: the client never verifies it.
///
/// Expirations are computed from the current time at call time, so no committed token turns red
/// when a date passes. The base64url encoder lives here on purpose: it is the independent
/// counterpart of the production decoder, never a call to it.
enum SessionTestTokenFactory {
    static let email = "reader@example.com"

    static let userID: UUID = {
        guard let id = UUID(uuidString: "596D4DB5-6C1A-4E2B-9F3D-7A8B9C0D1E2F") else {
            preconditionFailure("Invalid UUID literal in SessionTestTokenFactory")
        }
        return id
    }()

    private static let header = base64URL(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
    private static let signature = base64URL(Data("synthetic-signature".utf8))

    // MARK: - Tokens by age

    /// Just issued: 24 h left, more than the 23 h under which a token is renewed.
    static func fresh(email: String = SessionTestTokenFactory.email) -> String {
        makeJWT(expiringIn: 24 * 3600, email: email)
    }

    /// Issued more than an hour ago: 2 h left, so it must be renewed before use.
    static func aging(email: String = SessionTestTokenFactory.email) -> String {
        makeJWT(expiringIn: 2 * 3600, email: email)
    }

    /// Expired a minute ago.
    static func expired(email: String = SessionTestTokenFactory.email) -> String {
        makeJWT(expiringIn: -60, email: email)
    }

    /// A token whose `exp` is `seconds` from now (negative: in the past), with decimals.
    static func makeJWT(
        expiringIn seconds: TimeInterval,
        email: String = SessionTestTokenFactory.email,
        userID: UUID = SessionTestTokenFactory.userID
    ) -> String {
        makeJWT(exp: expSeconds(fromNow: seconds), email: email, userID: userID)
    }

    /// `seconds` from now as seconds since 1970, with a fixed fractional part like the backend's.
    static func expSeconds(fromNow seconds: TimeInterval) -> Double {
        (Date.now.timeIntervalSince1970 + seconds).rounded(.down) + 0.82
    }

    // MARK: - Tokens by payload

    static func makeJWT(
        exp: Double,
        email: String = SessionTestTokenFactory.email,
        userID: UUID = SessionTestTokenFactory.userID,
        filler: String = ""
    ) -> String {
        makeJWT(payloadJSON: payloadJSON(exp: exp, email: email, userID: userID, filler: filler))
    }

    /// A token whose payload segment is exactly the base64url of `payloadJSON`.
    static func makeJWT(payloadJSON: String) -> String {
        [header, base64URL(Data(payloadJSON.utf8)), signature].joined(separator: ".")
    }

    /// A token whose payload segment length leaves `remainder` modulo 4 (0, 2 or 3; 1 is not a
    /// possible base64 length), obtained by growing a `pad` claim the app ignores.
    static func makeJWT(exp: Double, payloadLengthRemainder remainder: Int) -> String? {
        for fillerLength in 0..<3 {
            let token = makeJWT(exp: exp, filler: String(repeating: "x", count: fillerLength))
            if payloadSegment(of: token).map({ $0.count % 4 }) == remainder {
                return token
            }
        }
        return nil
    }

    /// The payload JSON the backend emits, plus an ignored `pad` claim.
    static func payloadJSON(
        exp: Double,
        email: String = SessionTestTokenFactory.email,
        userID: UUID = SessionTestTokenFactory.userID,
        filler: String = ""
    ) -> String {
        #"{"exp":\#(exp),"iat":\#(exp - 24 * 3600),"email":"\#(email)","user_id":"\#(userID.uuidString)","sub":"saotome-manga","pad":"\#(filler)"}"#
    }

    /// The second segment of `token`, if it has one.
    static func payloadSegment(of token: String) -> String? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        return segments.count > 1 ? String(segments[1]) : nil
    }

    // MARK: - Unreadable tokens

    /// Tokens the app must reject as unreadable: (what is wrong with it, token).
    static let unreadable: [(String, String)] = {
        let future = expSeconds(fromNow: 24 * 3600)
        let validPayload = base64URL(Data(payloadJSON(exp: future).utf8))
        let email = SessionTestTokenFactory.email
        let userIDString = SessionTestTokenFactory.userID.uuidString
        return [
            ("empty string", ""),
            ("two segments", "\(header).\(validPayload)"),
            ("four segments", "\(header).\(validPayload).\(signature).\(signature)"),
            ("payload outside the base64url alphabet", "\(header).eyJle*HAiOjF9.\(signature)"),
            ("payload with an impossible base64 length", "\(header).eyJle.\(signature)"),
            ("payload that is not JSON", makeJWT(payloadJSON: "not json")),
            ("payload without exp", makeJWT(payloadJSON: #"{"email":"\#(email)","user_id":"\#(userIDString)"}"#)),
            ("payload without email", makeJWT(payloadJSON: #"{"exp":\#(future),"user_id":"\#(userIDString)"}"#)),
            ("payload without user_id", makeJWT(payloadJSON: #"{"exp":\#(future),"email":"\#(email)"}"#)),
            ("user_id that is not a UUID", makeJWT(payloadJSON: #"{"exp":\#(future),"email":"\#(email)","user_id":"42"}"#)),
        ]
    }()

    // MARK: - Encoding

    /// Base64url without padding (RFC 7515): `+` → `-`, `/` → `_`, no trailing `=`.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
