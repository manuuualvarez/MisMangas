//
//  CollectionTestSupport.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData

/// Inputs and store readings shared by the collection synchronization tests: the real
/// `collection_response.json` entries and entries derived from them, stored mangas to hang
/// entries from, blocked operations, and fresh-context reads of entries and the outbox.
enum CollectionTestSupport {
    /// The account of a signed-in session: the email the fakes sign in with, lowercased, as the
    /// session hands it to every write and to the drain.
    static let account = "reader@example.com"

    /// Another account, whose queued operations a session of `account` must never send.
    static let otherAccount = "other@example.com"

    /// A service over `actor`. With an account it reaches the collection on the server through a
    /// repository whose session is `security`; without one it is the guest's, which stays on the
    /// device.
    static func makeService(actor: MangaSyncActor, account: String?, security: any SecurityData) -> MangaSyncService {
        let mangaRepository = DefaultMangaRepositoryTest()
        return MangaSyncService(
            syncActor: actor,
            mangaRepository: mangaRepository,
            taxonomyCache: TaxonomyCacheActor(mangaRepository: mangaRepository),
            collectionRepository: account == nil ? nil : DefaultCollectionRepositoryTest(security: security),
            account: account
        )
    }

    /// The two entries of `collection_response.json`: Monster (id 1) and Berserk (id 2).
    static func remoteCollection() throws -> [UserMangaCollectionDTO] {
        try JSONDecoder.app.decode([UserMangaCollectionDTO].self, from: TestFixtures.data("collection_response.json"))
    }

    /// Monster as `/search/manga/1` serves it; other ids are derived from it with `replacing(id:)`.
    static func monster() throws -> MangaDTO {
        try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_monster.json"))
    }

    /// Caches one manga per id (Monster with the id replaced), so entries can hang from them.
    static func storeMangas(_ ids: [Int], in actor: MangaSyncActor, now: Date = .now) async throws {
        let base = try monster()
        for id in ids {
            _ = try await actor.cacheDetail(base.replacing(id: id), now: now)
        }
    }

    /// Blocks the queued operation of `mangaID` by failing it three times, as the drain does.
    static func block(mangaID: Int, in actor: MangaSyncActor, container: ModelContainer, now: Date) async throws {
        let context = PersistenceTestSupport.freshContext(container)
        let descriptor = FetchDescriptor<PendingOperation>(predicate: #Predicate { $0.mangaID == mangaID })
        guard let id = try context.fetch(descriptor).first?.id else {
            throw MissingOperation(mangaID: mangaID)
        }
        for _ in 0..<3 {
            _ = try await actor.markOperationFailed(id: id, error: "server", now: now)
        }
    }

    struct MissingOperation: Error, CustomStringConvertible {
        let mangaID: Int
        var description: String {
            "No queued operation for manga \(mangaID)"
        }
    }

    /// Stored entries sorted by manga id.
    static func entries(in context: ModelContext) throws -> [UserCollectionEntry] {
        try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context, sortBy: [SortDescriptor(\.mangaID)])
    }

    /// The stored entry of `mangaID`, if any.
    static func entry(mangaID: Int, in context: ModelContext) throws -> UserCollectionEntry? {
        try entries(in: context).first { $0.mangaID == mangaID }
    }

    /// Queued operations, oldest first.
    static func operations(in context: ModelContext) throws -> [PendingOperation] {
        try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context, sortBy: [SortDescriptor(\.createdAt)])
    }

    /// Queued operations sorted by manga id, for tests that read them by manga.
    static func operationsByManga(in context: ModelContext) throws -> [PendingOperation] {
        try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context, sortBy: [SortDescriptor(\.mangaID)])
    }
}

extension UserMangaCollectionDTO {
    /// A copy with another manga id (nested manga included) or other user fields.
    func replacing(
        mangaID: Int? = nil,
        volumesOwned: [Int]? = nil,
        completeCollection: Bool? = nil
    ) -> UserMangaCollectionDTO {
        UserMangaCollectionDTO(
            id: mangaID == nil ? id : UUID(),
            manga: mangaID.map { manga.replacing(id: $0) } ?? manga,
            volumesOwned: volumesOwned ?? self.volumesOwned,
            readingVolume: readingVolume,
            completeCollection: completeCollection ?? self.completeCollection
        )
    }
}
