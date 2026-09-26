//
//  AsyncCondition.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

/// Waits for an effect that production code produces on tasks the test does not await, such as a
/// service consuming a stream or a pass started by a request. Polls `condition` every few
/// milliseconds and returns `true` as soon as it holds, or `false` once `timeout` elapses or the
/// calling task is cancelled, so a missing effect fails the test instead of hanging it.
enum AsyncCondition {
    static func waitUntil(timeout: Duration = .seconds(5), _ condition: () throws -> Bool) async rethrows -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if try condition() {
                return true
            }
            guard ContinuousClock.now < deadline else {
                return false
            }
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return false
            }
        }
    }
}
