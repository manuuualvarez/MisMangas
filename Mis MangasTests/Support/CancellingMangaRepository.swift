//
//  CancellingMangaRepository.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 16/09/2026.
//

import Foundation
@testable import Mis_Mangas

/// Test conformer of `MangaRepository` that reproduces "the page arrived, but the caller has
/// already been cancelled": `fetchMangas(page:per:)` cancels the current task and then returns
/// the real `mangas_page.json` page without touching the transport. Every other endpoint keeps
/// the production implementation over the mocked `session`, so nothing can reach a real backend.
struct CancellingMangaRepository: MangaRepository {
    let session: URLSession

    nonisolated init() {
        session = URLSessionMockInterface.makeSession()
    }

    func fetchMangas(page _: Int, per _: Int) async throws(APIError) -> MangaPageDTO {
        withUnsafeCurrentTask { $0?.cancel() }
        do {
            return try JSONDecoder.app.decode(MangaPageDTO.self, from: TestFixtures.data("mangas_page.json"))
        } catch {
            throw .decoding(error)
        }
    }
}
