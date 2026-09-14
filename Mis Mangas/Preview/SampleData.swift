//
//  SampleData.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import SwiftData

/// Sample store for previews: 11 authors, 12 real backend records (ids and covers as the API
/// serves them) covering every status, and the "all" and "best" catalog indexes. Built in code
/// so previews never depend on a bundle; covers download like in the app.
enum SampleData {
    /// Inserts the sample data into `context` and saves. Previews are the only place that
    /// writes to a context outside `MangaSyncActor`.
    static func load(into context: ModelContext) throws {
        let fixture = Fixture()
        for author in fixture.authors {
            context.insert(author)
        }
        for manga in fixture.mangas {
            context.insert(manga)
        }
        for entry in fixture.entries {
            context.insert(entry)
        }
        try context.save()
    }

    private struct Fixture {
        let authors: [Author]
        let mangas: [Manga]
        let entries: [CatalogEntry]

        init() {
            let toriyama = Self.author("Akira", "Toriyama", .storyAndArt)
            let oda = Self.author("Eiichiro", "Oda", .storyAndArt)
            let isayama = Self.author("Hajime", "Isayama", .storyAndArt)
            let ishida = Self.author("Sui", "Ishida", .storyAndArt)
            let miura = Self.author("Kentarou", "Miura", .storyAndArt)
            let togashi = Self.author("Yoshihiro", "Togashi", .storyAndArt)
            let inoue = Self.author("Takehiko", "Inoue", .storyAndArt)
            let takeuchi = Self.author("Naoko", "Takeuchi", .storyAndArt)
            let azuma = Self.author("Kiyohiko", "Azuma", .storyAndArt)
            let ohba = Self.author("Tsugumi", "Ohba", .story)
            let obata = Self.author("Takeshi", "Obata", .art)
            authors = [toriyama, oda, isayama, ishida, miura, togashi, inoue, takeuchi, azuma, ohba, obata]

            let now = Date.now
            let day: TimeInterval = 86_400

            let dragonBall = Self.manga(
                id: 42, title: "Dragon Ball", english: "Dragon Ball", japanese: "ドラゴンボール",
                synopsis: "Son Goku, a boy with a monkey tail, searches for the seven Dragon Balls and grows into the strongest martial artist on Earth.",
                status: .finished, score: 8.41, start: (1984, 11, 20), end: (1995, 6, 5), chapters: 520, volumes: 42,
                cover: "https://cdn.myanimelist.net/images/manga/1/267793l.jpg",
                genres: [.action, .adventure, .comedy, .fantasy], themes: [.martialArts], demographics: [.shounen],
                cachedAt: now, authors: [toriyama]
            )
            let drSlump = Self.manga(
                id: 796, title: "Dr. Slump", english: "Dr. Slump", japanese: "Dr.スランプ",
                synopsis: "Inventor Senbei Norimaki builds Arale, an impossibly strong robot girl, in the odd little Penguin Village.",
                status: .finished, score: 7.71, start: (1980, 1, 28), end: (1984, 9, 24), chapters: 236, volumes: 18,
                cover: "https://cdn.myanimelist.net/images/manga/2/156408l.jpg", genres: [.comedy, .sciFi], themes: [.parody, .gagHumor], demographics: [.shounen],
                cachedAt: now.addingTimeInterval(-9 * day), authors: [toriyama]
            )
            let onePiece = Self.manga(
                id: 13, title: "One Piece", english: "One Piece", japanese: "ワンピース",
                synopsis: "Monkey D. Luffy and the Straw Hat crew sail the Grand Line in search of the legendary treasure of the Pirate King.",
                status: .publishing, score: 9.22, start: (1997, 7, 22), end: nil, chapters: nil, volumes: 107,
                cover: "https://cdn.myanimelist.net/images/manga/2/253146l.jpg",
                genres: [.action, .adventure, .fantasy], themes: [], demographics: [.shounen],
                cachedAt: now, authors: [oda]
            )
            let attackOnTitan = Self.manga(
                id: 23390, title: "Shingeki no Kyojin", english: "Attack on Titan", japanese: "進撃の巨人",
                synopsis: "Humanity lives behind walls to survive the Titans. Eren Yeager swears to wipe them out after his home falls.",
                status: .finished, score: 8.55, start: (2009, 9, 9), end: (2021, 4, 9), chapters: 141, volumes: 34,
                cover: "https://cdn.myanimelist.net/images/manga/2/37846l.jpg",
                genres: [.action, .drama, .mystery, .suspense], themes: [.gore, .military, .survival], demographics: [.shounen],
                cachedAt: now, authors: [isayama]
            )
            let tokyoGhoul = Self.manga(
                id: 33327, title: "Tokyo Ghoul", english: "Tokyo Ghoul", japanese: "東京喰種",
                synopsis: "Ken Kaneki becomes half ghoul after an organ transplant and has to survive between two worlds at war.",
                status: .discontinued, score: 8.52, // status changed on purpose: the sample must show every status
                start: (2011, 9, 8), end: (2014, 9, 18), chapters: 144, volumes: 14,
                cover: "https://cdn.myanimelist.net/images/manga/3/114037l.jpg", genres: [.action, .horror, .mystery, .supernatural], themes: [.gore, .psychological], demographics: [.seinen],
                cachedAt: nil, authors: [ishida]
            )
            let berserk = Self.manga(
                id: 2, title: "Berserk", english: "Berserk", japanese: "ベルセルク",
                synopsis: "Guts, the Black Swordsman, crosses a dark medieval world to avenge the demon who destroyed everything he loved.",
                status: .publishing, score: 9.47, start: (1989, 8, 25), end: nil, chapters: nil, volumes: 41,
                cover: "https://cdn.myanimelist.net/images/manga/1/157897l.jpg",
                genres: [.action, .adventure, .awardWinning, .drama, .fantasy, .horror], themes: [.gore, .military, .mythology, .psychological], demographics: [.seinen],
                cachedAt: now, authors: [miura]
            )
            let hunterXHunter = Self.manga(
                id: 26, title: "Hunter x Hunter", english: "Hunter x Hunter", japanese: "ハンター×ハンター",
                synopsis: "Gon Freecss sets out to become a Hunter and find his father, gathering friends in a world of strange creatures and Nen.",
                status: .publishing, score: 8.73, start: (1998, 3, 16), end: nil, chapters: nil, volumes: 37,
                cover: "https://cdn.myanimelist.net/images/manga/2/253119l.jpg", genres: [.action, .adventure, .fantasy], themes: [.superPower], demographics: [.shounen],
                cachedAt: now, authors: [togashi]
            )
            let yuYuHakusho = Self.manga(
                id: 53, title: "Yuu☆Yuu☆Hakusho", english: "Yu Yu Hakusho", japanese: "幽☆遊☆白書",
                synopsis: "Yusuke Urameshi dies saving a child and returns as a spirit detective solving supernatural cases.",
                status: .finished, score: 8.2, start: (1990, 12, 3), end: (1994, 7, 25), chapters: 175, volumes: 19,
                cover: nil, // cover removed on purpose: the sample must show the placeholder
                genres: [.action, .comedy, .supernatural], themes: [.martialArts], demographics: [.shounen],
                cachedAt: nil, authors: [togashi]
            )
            let vagabond = Self.manga(
                id: 656, title: "Vagabond", english: "Vagabond", japanese: "バガボンド",
                synopsis: "A retelling of the life of the legendary swordsman Miyamoto Musashi and his search for perfection through the blade.",
                status: .onHiatus, score: 9.24, start: (1998, 9, 3), end: nil, chapters: 327, volumes: 37,
                cover: "https://cdn.myanimelist.net/images/manga/1/259070l.jpg",
                genres: [.action, .adventure, .awardWinning, .drama], themes: [.historical, .samurai, .martialArts], demographics: [.seinen],
                cachedAt: now, authors: [inoue]
            )
            let sailorMoon = Self.manga(
                id: 92, title: "Bishoujo Senshi Sailor Moon", english: "Sailor Moon", japanese: "美少女戦士セーラームーン",
                synopsis: "Usagi Tsukino and her friends discover they are guardians of the cosmos destined to protect the Earth.",
                status: .finished, score: 8.2, start: (1991, 12, 28), end: (1997, 2, 3), chapters: 60, volumes: 18,
                cover: "https://cdn.myanimelist.net/images/manga/4/260613l.jpg", genres: [.adventure, .fantasy, .romance], themes: [.mahouShoujo, .school], demographics: [.shoujo],
                cachedAt: now.addingTimeInterval(-10 * day), authors: [takeuchi]
            )
            let yotsubato = Self.manga(
                id: 104, title: "Yotsuba to!", english: "Yotsuba&!", japanese: "よつばと！",
                synopsis: "Yotsuba discovers the everyday world with boundless curiosity alongside her adoptive father and the neighbours.",
                status: .publishing, score: 8.88, start: (2003, 3, 21), end: nil, chapters: nil, volumes: 15,
                cover: "https://cdn.myanimelist.net/images/manga/5/259524l.jpg", genres: [.comedy, .sliceOfLife], themes: [.childcare, .iyashikei], demographics: [.shounen],
                cachedAt: now, authors: [azuma]
            )
            let deathNote = Self.manga(
                id: 21, title: "Death Note", english: "Death Note", japanese: "デスノート",
                synopsis: "Light Yagami finds a notebook that kills whoever is written in it and sets out to reshape the world.",
                status: .finished, score: 8.7, start: (2003, 12, 1), end: (2006, 5, 15), chapters: 108, volumes: 12,
                cover: "https://cdn.myanimelist.net/images/manga/1/258245l.jpg",
                genres: [.supernatural, .suspense], themes: [.psychological, .detective], demographics: [.shounen],
                cachedAt: now, authors: [ohba, obata]
            )
            mangas = [
                dragonBall, drSlump, onePiece, attackOnTitan, tokyoGhoul, berserk,
                hunterXHunter, yuYuHakusho, vagabond, sailorMoon, yotsubato, deathNote
            ]

            let best = mangas.sorted { $0.score > $1.score }
            entries = Self.index("all", mangas, fetchedAt: now) + Self.index("best", best, fetchedAt: now)
        }

        private static func author(_ firstName: String, _ lastName: String, _ role: AuthorRole) -> Author {
            Author(id: UUID(), firstName: firstName, lastName: lastName, role: role.rawValue)
        }

        private static func manga(
            id: Int, title: String, english: String?, japanese: String?, synopsis: String,
            status: MangaStatus, score: Double, start: (Int, Int, Int)?, end: (Int, Int, Int)?,
            chapters: Int?, volumes: Int?, cover: String?,
            genres: [Genre], themes: [Theme], demographics: [Demographic],
            cachedAt: Date?, authors: [Author]
        ) -> Manga {
            let manga = Manga(
                id: id, title: title, titleEnglish: english, titleJapanese: japanese, synopsis: synopsis,
                status: status.rawValue, score: score,
                startDate: start.map(date), endDate: end.map(date),
                chapters: chapters, volumes: volumes, mainPictureURL: cover,
                url: "https://myanimelist.net/manga/\(id)",
                genres: genres.map(\.rawValue), themes: themes.map(\.rawValue), demographics: demographics.map(\.rawValue),
                cachedAt: cachedAt
            )
            manga.authors = authors
            return manga
        }

        private static func index(_ modeKey: String, _ mangas: [Manga], fetchedAt: Date) -> [CatalogEntry] {
            mangas.enumerated().map { ordinal, manga in
                let entry = CatalogEntry(modeKey: modeKey, ordinal: ordinal, fetchedAt: fetchedAt)
                entry.manga = manga
                return entry
            }
        }

        private static func date(_ ymd: (Int, Int, Int)) -> Date {
            var components = DateComponents()
            components.year = ymd.0
            components.month = ymd.1
            components.day = ymd.2
            guard let date = Calendar(identifier: .gregorian).date(from: components) else {
                preconditionFailure("Invalid sample date \(ymd)")
            }
            return date
        }
    }
}
