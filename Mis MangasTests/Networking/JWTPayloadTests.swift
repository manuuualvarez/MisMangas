//
//  JWTPayloadTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// Local reading of the session JWT: `decodeJWTPayload` splits the token, decodes the payload
/// segment from base64url without padding and reads `exp`, `email` and `user_id`. Oracles: the
/// claims put into the synthetic tokens of `SessionTestTokenFactory` (whose base64url encoder is
/// independent of production) and the payload shape verified against the live API.
@Suite("JWTPayload")
struct JWTPayloadTests {
    /// `exp` of a real token as the backend emits it: seconds since 1970 with decimals.
    private static let liveExp = 1_790_365_492.82

    @Test func `Reads exp with decimals, email and user_id from the payload the backend emits`() throws {
        let token = SessionTestTokenFactory.makeJWT(exp: Self.liveExp)

        let payload = try decodeJWTPayload(token)

        #expect(payload.exp == Date(timeIntervalSince1970: Self.liveExp))
        #expect(payload.email == SessionTestTokenFactory.email)
        #expect(payload.userID == SessionTestTokenFactory.userID)
    }

    @Test(arguments: [0, 2, 3])
    func `Decodes a payload segment without padding whatever its length modulo 4`(remainder: Int) throws {
        let token = try #require(SessionTestTokenFactory.makeJWT(exp: Self.liveExp, payloadLengthRemainder: remainder))
        let segment = try #require(SessionTestTokenFactory.payloadSegment(of: token))
        try #require(segment.count % 4 == remainder)
        try #require(!segment.contains("="))

        let payload = try decodeJWTPayload(token)

        #expect(payload.email == SessionTestTokenFactory.email)
        #expect(payload.userID == SessionTestTokenFactory.userID)
        #expect(payload.exp == Date(timeIntervalSince1970: Self.liveExp))
    }

    @Test func `Decodes a payload segment that uses the url-safe characters - and _`() throws {
        // A run of `~` encodes to `+` and a run of `?` to `/` in standard base64; base64url turns
        // them into `-` and `_`.
        let token = SessionTestTokenFactory.makeJWT(exp: Self.liveExp, filler: "~~~~~~??????")
        let segment = try #require(SessionTestTokenFactory.payloadSegment(of: token))
        try #require(segment.contains("-"))
        try #require(segment.contains("_"))

        let payload = try decodeJWTPayload(token)

        #expect(payload.email == SessionTestTokenFactory.email)
        #expect(payload.userID == SessionTestTokenFactory.userID)
    }

    @Test(arguments: SessionTestTokenFactory.unreadable)
    func `An unreadable token throws invalidToken`(reason: String, token: String) {
        expectAuthError(.invalidToken) {
            try decodeJWTPayload(token)
        }
    }
}
