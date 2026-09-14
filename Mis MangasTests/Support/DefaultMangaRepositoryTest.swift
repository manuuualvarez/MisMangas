//
//  DefaultMangaRepositoryTest.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas

/// Test conformer of `MangaRepository`. The only thing it replaces is the `session` seam
/// inherited from `NetworkInteractor`: an ephemeral `URLSession` whose transport is
/// `URLSessionMockInterface`. Everything else — endpoints, `URLRequest.request`, `getJSON`,
/// status mapping, decoding — is the production code of `extension MangaRepository`.
struct DefaultMangaRepositoryTest: MangaRepository {
    let session: URLSession

    nonisolated init() {
        session = URLSessionMockInterface.makeSession()
    }
}
