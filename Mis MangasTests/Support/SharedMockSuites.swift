//
//  SharedMockSuites.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Testing

/// Parent of every suite that mutates the global `CatalogMockScenario` slot.
///
/// Swift Testing runs suites in parallel; `.serialized` applies to this suite and to every
/// nested one, so declaring a suite as `extension SharedMockSuites { @Suite struct X { … } }`
/// serializes it against all the other mock users in-process. Suites that never touch the
/// mock (pure decoding, enums) stay outside and keep running in parallel.
@Suite("Shared-mock suites (serialized)", .serialized)
struct SharedMockSuites {}
