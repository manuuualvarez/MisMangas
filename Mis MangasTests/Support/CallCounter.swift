//
//  CallCounter.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Synchronization

/// Counts calls of a `@Sendable` callback (for instance `onCollectionChanged`) from any thread.
final class CallCounter: Sendable {
    private let count = Mutex(0)

    func increment() {
        count.withLock { $0 += 1 }
    }

    var value: Int {
        count.withLock { $0 }
    }
}
