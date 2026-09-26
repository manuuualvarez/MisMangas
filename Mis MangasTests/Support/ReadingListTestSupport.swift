//
//  ReadingListTestSupport.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData

/// Seeds the store exactly as a reading-list test describes it, through a fresh context and an
/// explicit `save()`, so every date (the manga's and the entry's) is chosen by the test and none
/// of it goes through the code under test.
enum ReadingListTestSupport {
    /// The user's side of a seeded manga.
    struct Entry {
        var readingVolume: Int?
        var completeCollection = false
        var volumesOwned: [Int] = []
        /// Stamped as both `createdAt` and `updatedAt` of the entry.
        var updatedAt: Date
    }

    /// Stores one manga and, with `entry`, its collection entry (the manga then counts as in the
    /// collection).
    static func insertManga(
        id: Int,
        title: String = "Manga",
        volumes: Int?,
        coverURL: String? = nil,
        updatedAt: Date,
        entry: Entry?,
        in container: ModelContainer
    ) throws {
        let context = PersistenceTestSupport.freshContext(container)
        let manga = Manga(
            id: id,
            title: title,
            status: MangaStatus.finished.rawValue,
            score: 8,
            volumes: volumes,
            mainPictureURL: coverURL,
            inCollection: entry != nil,
            updatedAt: updatedAt
        )
        context.insert(manga)
        if let entry {
            let stored = UserCollectionEntry(
                mangaID: id,
                volumesOwned: entry.volumesOwned,
                readingVolume: entry.readingVolume,
                completeCollection: entry.completeCollection,
                createdAt: entry.updatedAt,
                updatedAt: entry.updatedAt
            )
            context.insert(stored)
            stored.manga = manga
        }
        try context.save()
    }

    /// Queues an operation for `mangaID` as an earlier change would have left it.
    static func queueOperation(
        _ type: PendingOperationType,
        mangaID: Int,
        account: String?,
        createdAt: Date,
        in container: ModelContainer
    ) throws {
        let context = PersistenceTestSupport.freshContext(container)
        context.insert(PendingOperation(operationType: type, mangaID: mangaID, payload: nil, createdAt: createdAt, account: account))
        try context.save()
    }

    /// The body an `.upsert` operation will upload, decoded as the server will read it.
    static func request(of operation: PendingOperation) throws -> UserMangaCollectionRequest {
        guard let payload = operation.payload else {
            throw MissingPayload(mangaID: operation.mangaID)
        }
        return try JSONDecoder.app.decode(UserMangaCollectionRequest.self, from: payload)
    }

    struct MissingPayload: Error, CustomStringConvertible {
        let mangaID: Int
        var description: String {
            "The queued operation of manga \(mangaID) carries no payload"
        }
    }
}
