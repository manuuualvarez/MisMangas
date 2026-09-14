//
//  MangaDTO+Model.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// DTO → `Manga`. Builds or refreshes the stored model; inserting it and stamping `cachedAt`
/// and `updatedAt` is the actor's job.
extension MangaDTO {
    /// A new, not yet inserted `Manga` with every server field copied.
    func makeManga() -> Manga {
        let manga = Manga(id: id, title: title, status: status.rawValue, score: score)
        apply(to: manga)
        return manga
    }

    /// Copies the server fields onto an existing manga. Leaves `cachedAt`, `inCollection`,
    /// `updatedAt` and the relationships untouched.
    func apply(to manga: Manga) {
        manga.title = title
        manga.titleEnglish = titleEnglish
        manga.titleJapanese = titleJapanese
        manga.synopsis = synopsis
        manga.background = background
        manga.status = status.rawValue
        manga.score = score
        manga.startDate = startDate
        manga.endDate = endDate
        manga.chapters = chapters
        manga.volumes = volumes
        manga.mainPictureURL = mainPicture
        manga.url = url
        manga.genres = genres.map(\.genre)
        manga.themes = themes.map(\.theme)
        manga.demographics = demographics.map(\.demographic)
    }
}
