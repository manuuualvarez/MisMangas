//
//  DefaultCollectionRepositoryTest.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas

/// Test conformer of `CollectionRepository`. It replaces only the seams: the `session` inherited
/// from `NetworkInteractor` (transport = `URLSessionMockInterface`) and the `security` that
/// provides the token (a `FakeSecurity`, or a `SecurityTestConformer` when the test exercises
/// the real renewal). Endpoints, requests, status mapping and decoding are the production code of
/// `extension CollectionRepository`.
struct DefaultCollectionRepositoryTest: CollectionRepository {
    let security: any SecurityData
    let session: URLSession

    nonisolated init(security: any SecurityData) {
        self.security = security
        session = URLSessionMockInterface.makeSession()
    }
}
