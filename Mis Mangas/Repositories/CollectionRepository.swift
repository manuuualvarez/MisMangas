//
//  CollectionRepository.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// The user's collection on the server (`/collection/manga`). Every call is authenticated with
/// the session JWT, obtained from `security.validToken()` right before the request, so a token
/// about to expire is renewed first. A session that cannot provide a token ends as
/// `APIError.unauthorized` without reaching the collection endpoints. `Sendable` is required: the
/// existential of a protocol isolated to a global actor is not `Sendable` by itself, and the sync
/// service holds it outside `@APIActor`.
@APIActor
protocol CollectionRepository: NetworkInteractor, Sendable {
    var security: any SecurityData { get }

    func fetchCollection() async throws(APIError) -> [UserMangaCollectionDTO]
    func upsert(_ request: UserMangaCollectionRequest) async throws(APIError)
    func delete(mangaID: Int) async throws(APIError)
}

/// Production conformer: the uncached `URLSession.authenticated`, so the user's collection never
/// lands in a disk cache.
struct DefaultCollectionRepository: CollectionRepository {
    let security: any SecurityData

    var session: URLSession { .authenticated }

    nonisolated init(security: any SecurityData) {
        self.security = security
    }
}

extension CollectionRepository {
    func fetchCollection() async throws(APIError) -> [UserMangaCollectionDTO] {
        let request = try URLRequest.request(url: .collection, token: await token())
        return try await getJSON(request: request, type: [UserMangaCollectionDTO].self)
    }

    /// Creates or updates the entry; the server answers 201 without a body.
    func upsert(_ request: UserMangaCollectionRequest) async throws(APIError) {
        let urlRequest = try URLRequest.request(url: .collection, method: .post, body: request, token: await token())
        try await getStatus(request: urlRequest)
    }

    /// A manga the server does not have in the collection answers 404 (`.notFound`).
    func delete(mangaID: Int) async throws(APIError) {
        let request = try URLRequest.request(url: .collectionItem(id: mangaID), method: .delete, token: await token())
        try await getStatus(request: request)
    }

    /// The session token, renewed first when needed. A session that cannot provide one becomes
    /// `.unauthorized` before any request. Any other failure of the renewal (no connection, a
    /// refusal other than 401, an unreadable answer) is transient: it says nothing about the
    /// operation being sent, so it must never make the caller discard it.
    private func token() async throws(APIError) -> String {
        do {
            return try await security.validToken()
        } catch {
            switch error {
            case .sessionExpired, .invalidToken, .invalidCredentials:
                throw .unauthorized
            case .offline:
                throw .transport(URLError(.notConnectedToInternet))
            case .server(.cancelled):
                throw .cancelled
            case .server(let apiError):
                throw .transport(apiError)
            case .keychain, .invalidEmail, .weakPassword, .emailAlreadyRegistered:
                throw .transport(error)
            }
        }
    }
}
