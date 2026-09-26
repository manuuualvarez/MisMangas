//
//  WatchTransportErrorAssertions.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

@testable import Mis_Mangas
import Testing

/// Runs `operation` and records an issue unless it throws `WatchTransportError.unrecognizedPayload`.
func expectUnrecognizedPayload<Value>(
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: () throws -> Value
) {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    do {
        _ = try operation()
        Issue.record("Expected WatchTransportError.unrecognizedPayload, but the operation completed", sourceLocation: sourceLocation)
    } catch {
        guard case .unrecognizedPayload? = error as? WatchTransportError else {
            Issue.record("Expected WatchTransportError.unrecognizedPayload, got \(error)", sourceLocation: sourceLocation)
            return
        }
    }
}

/// Runs `operation` and records an issue unless it throws `WatchTransportError.payloadTooLarge`.
func expectPayloadTooLarge<Value>(
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: () throws -> Value
) {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    do {
        _ = try operation()
        Issue.record("Expected WatchTransportError.payloadTooLarge, but the operation completed", sourceLocation: sourceLocation)
    } catch {
        guard case .payloadTooLarge? = error as? WatchTransportError else {
            Issue.record("Expected WatchTransportError.payloadTooLarge, got \(error)", sourceLocation: sourceLocation)
            return
        }
    }
}

/// Runs `operation` and records an issue unless it throws `WatchTransportError.decoding`, whatever
/// the decoder error it carries.
func expectDecodingError<Value>(
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: () throws -> Value
) {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    do {
        _ = try operation()
        Issue.record("Expected WatchTransportError.decoding, but the operation completed", sourceLocation: sourceLocation)
    } catch {
        guard case .decoding? = error as? WatchTransportError else {
            Issue.record("Expected WatchTransportError.decoding, got \(error)", sourceLocation: sourceLocation)
            return
        }
    }
}
