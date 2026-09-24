//
//  SyncErrorAssertions.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

@testable import Mis_Mangas
import Testing

/// Runs `operation` and records an issue unless it throws `SyncError.sessionExpired`.
func expectSessionExpired<Value>(
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: () async throws -> Value
) async {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    do {
        _ = try await operation()
        Issue.record("Expected SyncError.sessionExpired, but the operation completed", sourceLocation: sourceLocation)
    } catch {
        guard case .sessionExpired? = error as? SyncError else {
            Issue.record("Expected SyncError.sessionExpired, got \(error)", sourceLocation: sourceLocation)
            return
        }
    }
}
