//
//  MangaStatus.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Publication status as the API spells it. Unknown values fall back to `.none`.
enum MangaStatus: String, Codable {
    case publishing = "currently_publishing"
    case finished
    case onHiatus = "on_hiatus"
    case discontinued
    case none

    /// Unknown server values decode as `.none` instead of failing the whole `MangaDTO`.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .none
    }

    var displayName: String {
        switch self {
        case .publishing: String(localized: "Publishing")
        case .finished: String(localized: "Finished")
        case .onHiatus: String(localized: "On hiatus")
        case .discontinued: String(localized: "Discontinued")
        case .none: String(localized: "Unknown")
        }
    }
}
