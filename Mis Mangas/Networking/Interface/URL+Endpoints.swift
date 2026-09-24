//
//  URL+Endpoints.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

extension URL {
    /// Backend base URL. Validated once without a `!`.
    static let urlBase: URL = {
        guard let url = URL(string: "https://mymanga-acacademy-5607149ebe3d.herokuapp.com") else {
            preconditionFailure("Invalid base URL literal")
        }
        return url
    }()

    // MARK: - Catalog (/list)

    static let listGenres = urlBase.appending(path: "list/genres")
    static let listThemes = urlBase.appending(path: "list/themes")
    static let listDemographics = urlBase.appending(path: "list/demographics")
    static let listAuthorsByIDs = urlBase.appending(path: "list/authorsByIds")

    static func listMangas(page: Int, per: Int) -> URL {
        urlBase.appending(path: "list/mangas")
            .appending(queryItems: pageQuery(page: page, per: per))
    }

    static func listBestMangas(page: Int, per: Int) -> URL {
        urlBase.appending(path: "list/bestMangas")
            .appending(queryItems: pageQuery(page: page, per: per))
    }

    static func mangaByGenre(_ genre: String, page: Int, per: Int) -> URL {
        urlBase.appending(path: "list/mangaByGenre/\(genre)")
            .appending(queryItems: pageQuery(page: page, per: per))
    }

    static func mangaByTheme(_ theme: String, page: Int, per: Int) -> URL {
        urlBase.appending(path: "list/mangaByTheme/\(theme)")
            .appending(queryItems: pageQuery(page: page, per: per))
    }

    static func mangaByDemographic(_ demographic: String, page: Int, per: Int) -> URL {
        urlBase.appending(path: "list/mangaByDemographic/\(demographic)")
            .appending(queryItems: pageQuery(page: page, per: per))
    }

    static func mangaByAuthor(_ authorID: UUID, page: Int, per: Int) -> URL {
        urlBase.appending(path: "list/mangaByAuthor/\(authorID.uuidString)")
            .appending(queryItems: pageQuery(page: page, per: per))
    }

    static func listAuthorsPaged(page: Int, per: Int) -> URL {
        urlBase.appending(path: "list/authorsPaged")
            .appending(queryItems: pageQuery(page: page, per: per))
    }

    // MARK: - Search (/search)

    static func mangaByID(_ id: Int) -> URL {
        urlBase.appending(path: "search/manga/\(id)")
    }

    static func customSearch(page: Int, per: Int) -> URL {
        urlBase.appending(path: "search/manga")
            .appending(queryItems: pageQuery(page: page, per: per))
    }

    static func mangasBeginsWith(_ query: String) -> URL {
        urlBase.appending(path: "search/mangasBeginsWith/\(query)")
    }

    static func mangasContains(_ query: String, page: Int, per: Int) -> URL {
        urlBase.appending(path: "search/mangasContains/\(query)")
            .appending(queryItems: pageQuery(page: page, per: per))
    }

    static func authorSearch(_ query: String) -> URL {
        urlBase.appending(path: "search/author/\(query)")
    }

    // MARK: - Users and session (/users)

    static let createUser = urlBase.appending(path: "users")
    static let jwtLogin = urlBase.appending(path: "users/jwt/login")
    static let jwtRefresh = urlBase.appending(path: "users/jwt/refresh")
    static let jwtMe = urlBase.appending(path: "users/jwt/me")

    // MARK: - Collection (/collection)

    static let collection = urlBase.appending(path: "collection/manga")

    static func collectionItem(id: Int) -> URL {
        urlBase.appending(path: "collection/manga/\(id)")
    }

    // MARK: - Helpers

    /// `page` is 1-based; the app keeps `per` constant during a scroll session.
    static func pageQuery(page: Int, per: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per", value: String(per))
        ]
    }
}
