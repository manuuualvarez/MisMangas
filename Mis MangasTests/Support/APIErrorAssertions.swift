//
//  APIErrorAssertions.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

@testable import Mis_Mangas
import Testing

/// Comparable shape of an `APIError` (the production enum carries `any Error` payloads and is
/// deliberately not `Equatable`). `.http` compares the status; payload cases match by case only.
enum APIErrorCase: CustomStringConvertible {
    case invalidURL
    case transport
    case encoding
    case decoding
    case http(status: Int)
    case unauthorized
    case forbidden
    case notFound
    case serverError
    case cancelled
    case unknown

    func matches(_ error: APIError) -> Bool {
        switch (self, error) {
        case (.invalidURL, .invalidURL),
             (.transport, .transport),
             (.encoding, .encoding),
             (.decoding, .decoding),
             (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.notFound, .notFound),
             (.serverError, .serverError),
             (.cancelled, .cancelled),
             (.unknown, .unknown):
            true
        case (.http(let expected), .http(let status, _)):
            expected == status
        default:
            false
        }
    }

    var description: String {
        switch self {
        case .invalidURL: "invalidURL"
        case .transport: "transport"
        case .encoding: "encoding"
        case .decoding: "decoding"
        case .http(let status): "http(status: \(status))"
        case .unauthorized: "unauthorized"
        case .forbidden: "forbidden"
        case .notFound: "notFound"
        case .serverError: "serverError"
        case .cancelled: "cancelled"
        case .unknown: "unknown"
        }
    }
}

/// Runs `operation` and records an issue unless it throws an `APIError` matching `expected`.
/// Returns the thrown `APIError` (if any) so callers can inspect payloads.
@discardableResult
func expectAPIError<Value>(
    _ expected: APIErrorCase,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: () async throws -> Value
) async -> APIError? {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    do {
        _ = try await operation()
        Issue.record("Expected APIError.\(expected), but the operation completed", sourceLocation: sourceLocation)
        return nil
    } catch {
        return expectAPIError(expected, matches: error, at: sourceLocation)
    }
}

/// Records an issue unless `error` is an `APIError` matching `expected`. Useful for errors
/// obtained from `Task.result`, where typed throws are erased to `any Error`.
@discardableResult
func expectAPIError(
    _ expected: APIErrorCase,
    matches error: any Error,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column
) -> APIError? {
    expectAPIError(expected, matches: error, at: SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column))
}

private func expectAPIError(_ expected: APIErrorCase, matches error: any Error, at sourceLocation: SourceLocation) -> APIError? {
    guard let apiError = error as? APIError else {
        Issue.record("Expected APIError.\(expected), got \(error)", sourceLocation: sourceLocation)
        return nil
    }
    #expect(expected.matches(apiError), "Expected APIError.\(expected), got APIError\(apiError)", sourceLocation: sourceLocation)
    return apiError
}
