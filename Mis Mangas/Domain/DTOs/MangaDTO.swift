//
//  MangaDTO.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// A manga exactly as the API serves it (`/search/manga/{id}` and every page item).
/// Network contract only; persisted as `Manga` by `MangaSyncActor`.
struct MangaDTO: Codable, Hashable, Identifiable {
    let id: Int
    let title: String
    let titleEnglish: String?
    let titleJapanese: String?
    let synopsis: String?
    let background: String?
    let startDate: Date?
    let endDate: Date?
    let score: Double
    let status: MangaStatus
    let chapters: Int?
    let volumes: Int?
    let mainPicture: String?
    let url: String?
    let authors: [AuthorDTO]
    let genres: [GenreDTO]
    let themes: [ThemeDTO]
    let demographics: [DemographicDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case titleEnglish
        case titleJapanese
        case synopsis = "sypnosis" // sic: the backend misspells the key
        case background
        case startDate
        case endDate
        case score
        case status
        case chapters
        case volumes
        case mainPicture
        case url
        case authors
        case genres
        case themes
        case demographics
    }
}
