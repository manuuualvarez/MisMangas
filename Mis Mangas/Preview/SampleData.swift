//
//  SampleData.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Sample catalog for previews: 13 real backend records (ids and covers as the API serves them)
/// by 12 authors, covering every status, and a collection of 8 of them. Built once as DTOs, so
/// previews store them through the same actor as the app and `PreviewMangaRepository` serves them
/// as server pages.
enum SampleData {
    static let mangas: [MangaDTO] = Builder().mangas

    /// My collection as `/collection/manga` would serve it: 4 series being read, 3 complete (one
    /// without a reading volume) and 1 just started at volume 1.
    static let collection: [UserMangaCollectionDTO] = Builder.collection(of: mangas)

    /// The taxonomy lists as `/list/*` would serve them for this sample: every name that appears,
    /// once, in order of first appearance.
    static let genres: [String] = uniqueInOrder(mangas.flatMap { $0.genres.map(\.genre) })
    static let themes: [String] = uniqueInOrder(mangas.flatMap { $0.themes.map(\.theme) })
    static let demographics: [String] = uniqueInOrder(mangas.flatMap { $0.demographics.map(\.demographic) })

    /// The page the backend would send for `mode`: "all" in sample order, "best" by score, every
    /// filter and search over the sample with the server's matching rules (case-insensitive;
    /// exact names for categories). `total` is the size of the result, so a page of 20 is also
    /// the last one.
    static func page(for mode: CatalogMode, page: Int, per: Int) -> MangaPageDTO {
        let ordered: [MangaDTO]
        switch mode {
        case .all:
            ordered = mangas
        case .best:
            ordered = mangas.sorted { $0.score > $1.score }
        case .byGenre(let genre):
            ordered = mangas.filter { $0.genres.contains { sameName($0.genre, genre) } }
        case .byTheme(let theme):
            ordered = mangas.filter { $0.themes.contains { sameName($0.theme, theme) } }
        case .byDemographic(let demographic):
            ordered = mangas.filter { $0.demographics.contains { sameName($0.demographic, demographic) } }
        case .byAuthor(let id, _):
            ordered = mangas.filter { $0.authors.contains { $0.id == id } }
        case .titleContains(let query):
            ordered = mangas.filter { matches($0.title, query, contains: true) }
        case .beginsWith(let query):
            ordered = mangas.filter { matches($0.title, query, contains: false) }
        case .search(let search):
            ordered = mangas.filter { matches($0, search) }
        }
        let start = min(max(page - 1, 0) * per, ordered.count)
        let end = min(start + per, ordered.count)
        return MangaPageDTO(
            metadata: PageMetadataDTO(total: ordered.count, page: page, per: per),
            items: Array(ordered[start ..< end])
        )
    }

    /// `/search/author/{text}`: the sample's authors whose first or last name contains `text`.
    static func authors(matching text: String) -> [AuthorDTO] {
        var seen: Set<UUID> = []
        return mangas.flatMap(\.authors).filter { author in
            guard author.firstName.localizedCaseInsensitiveContains(text)
                || author.lastName.localizedCaseInsensitiveContains(text) else {
                return false
            }
            return seen.insert(author.id).inserted
        }
    }

    // MARK: - Matching

    private static func uniqueInOrder(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive) == .orderedSame
    }

    /// `nil` or blank criteria match everything; `contains` picks CONTAINS over BEGINS WITH.
    private static func matches(_ text: String, _ query: String?, contains: Bool) -> Bool {
        guard let query, !query.isEmpty else {
            return true
        }
        return contains
            ? text.localizedCaseInsensitiveContains(query)
            : text.lowercased().hasPrefix(query.lowercased())
    }

    /// AND of every present field of a `CustomSearch`; a manga must carry every listed category.
    private static func matches(_ manga: MangaDTO, _ search: CustomSearch) -> Bool {
        let contains = search.searchContains
        guard matches(manga.title, search.searchTitle, contains: contains) else {
            return false
        }
        let authorMatches = manga.authors.contains {
            matches($0.firstName, search.searchAuthorFirstName, contains: contains)
                && matches($0.lastName, search.searchAuthorLastName, contains: contains)
        }
        guard authorMatches || (search.searchAuthorFirstName == nil && search.searchAuthorLastName == nil) else {
            return false
        }
        let genres = manga.genres.map(\.genre)
        let themes = manga.themes.map(\.theme)
        let demographics = manga.demographics.map(\.demographic)
        return (search.searchGenres ?? []).allSatisfy { wanted in genres.contains { sameName($0, wanted) } }
            && (search.searchThemes ?? []).allSatisfy { wanted in themes.contains { sameName($0, wanted) } }
            && (search.searchDemographics ?? []).allSatisfy { wanted in demographics.contains { sameName($0, wanted) } }
    }

    private struct Builder {
        let mangas: [MangaDTO]

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
            let urasawa = Self.author("Naoki", "Urasawa", .storyAndArt)

            mangas = [
                Self.manga(
                    id: 42, title: "Dragon Ball", english: "Dragon Ball", japanese: "ドラゴンボール",
                    synopsis: "Son Goku, a boy with a monkey tail, searches for the seven Dragon Balls and grows into the strongest martial artist on Earth.",
                    status: .finished, score: 8.41, start: (1984, 11, 20), end: (1995, 6, 5), chapters: 520, volumes: 42,
                    cover: "https://cdn.myanimelist.net/images/manga/1/267793l.jpg",
                    genres: [.action, .adventure, .comedy, .fantasy], themes: [.martialArts], demographics: [.shounen],
                    authors: [toriyama]
                ),
                Self.manga(
                    id: 796, title: "Dr. Slump", english: "Dr. Slump", japanese: "Dr.スランプ",
                    synopsis: "Inventor Senbei Norimaki builds Arale, an impossibly strong robot girl, in the odd little Penguin Village.",
                    status: .finished, score: 7.71, start: (1980, 1, 28), end: (1984, 9, 24), chapters: 236, volumes: 18,
                    cover: "https://cdn.myanimelist.net/images/manga/2/156408l.jpg",
                    genres: [.comedy, .sciFi], themes: [.parody, .gagHumor], demographics: [.shounen],
                    authors: [toriyama]
                ),
                Self.manga(
                    id: 13, title: "One Piece", english: "One Piece", japanese: "ワンピース",
                    synopsis: "Monkey D. Luffy and the Straw Hat crew sail the Grand Line in search of the legendary treasure of the Pirate King.",
                    status: .publishing, score: 9.22, start: (1997, 7, 22), end: nil, chapters: nil, volumes: 107,
                    cover: "https://cdn.myanimelist.net/images/manga/2/253146l.jpg",
                    genres: [.action, .adventure, .fantasy], themes: [], demographics: [.shounen],
                    authors: [oda]
                ),
                Self.manga(
                    id: 23390, title: "Shingeki no Kyojin", english: "Attack on Titan", japanese: "進撃の巨人",
                    synopsis: "Humanity lives behind walls to survive the Titans. Eren Yeager swears to wipe them out after his home falls.",
                    status: .finished, score: 8.55, start: (2009, 9, 9), end: (2021, 4, 9), chapters: 141, volumes: 34,
                    cover: "https://cdn.myanimelist.net/images/manga/2/37846l.jpg",
                    genres: [.action, .drama, .mystery, .suspense], themes: [.gore, .military, .survival], demographics: [.shounen],
                    authors: [isayama]
                ),
                Self.manga(
                    id: 33327, title: "Tokyo Ghoul", english: "Tokyo Ghoul", japanese: "東京喰種",
                    synopsis: "Ken Kaneki becomes half ghoul after an organ transplant and has to survive between two worlds at war.",
                    status: .discontinued, score: 8.52, // status changed on purpose: the sample must show every status
                    start: (2011, 9, 8), end: (2014, 9, 18), chapters: 144, volumes: 14,
                    cover: "https://cdn.myanimelist.net/images/manga/3/114037l.jpg",
                    genres: [.action, .horror, .mystery, .supernatural], themes: [.gore, .psychological], demographics: [.seinen],
                    authors: [ishida]
                ),
                Self.manga(
                    id: 2, title: "Berserk", english: "Berserk", japanese: "ベルセルク",
                    synopsis: "Guts, the Black Swordsman, crosses a dark medieval world to avenge the demon who destroyed everything he loved.",
                    status: .publishing, score: 9.47, start: (1989, 8, 25), end: nil, chapters: nil, volumes: 41,
                    cover: "https://cdn.myanimelist.net/images/manga/1/157897l.jpg",
                    genres: [.action, .adventure, .awardWinning, .drama, .fantasy, .horror], themes: [.gore, .military, .mythology, .psychological], demographics: [.seinen],
                    authors: [miura]
                ),
                Self.manga(
                    id: 26, title: "Hunter x Hunter", english: "Hunter x Hunter", japanese: "ハンター×ハンター",
                    synopsis: "Gon Freecss sets out to become a Hunter and find his father, gathering friends in a world of strange creatures and Nen.",
                    status: .publishing, score: 8.73, start: (1998, 3, 16), end: nil, chapters: nil, volumes: 37,
                    cover: "https://cdn.myanimelist.net/images/manga/2/253119l.jpg",
                    genres: [.action, .adventure, .fantasy], themes: [.superPower], demographics: [.shounen],
                    authors: [togashi]
                ),
                Self.manga(
                    id: 53, title: "Yuu☆Yuu☆Hakusho", english: "Yu Yu Hakusho", japanese: "幽☆遊☆白書",
                    synopsis: "Yusuke Urameshi dies saving a child and returns as a spirit detective solving supernatural cases.",
                    status: .finished, score: 8.2, start: (1990, 12, 3), end: (1994, 7, 25), chapters: 175, volumes: 19,
                    cover: nil, // cover removed on purpose: the sample must show the placeholder
                    genres: [.action, .comedy, .supernatural], themes: [.martialArts], demographics: [.shounen],
                    authors: [togashi]
                ),
                Self.manga(
                    id: 656, title: "Vagabond", english: "Vagabond", japanese: "バガボンド",
                    synopsis: "A retelling of the life of the legendary swordsman Miyamoto Musashi and his search for perfection through the blade.",
                    status: .onHiatus, score: 9.24, start: (1998, 9, 3), end: nil, chapters: 327, volumes: 37,
                    cover: "https://cdn.myanimelist.net/images/manga/1/259070l.jpg",
                    genres: [.action, .adventure, .awardWinning, .drama], themes: [.historical, .samurai, .martialArts], demographics: [.seinen],
                    authors: [inoue]
                ),
                Self.manga(
                    id: 92, title: "Bishoujo Senshi Sailor Moon", english: "Sailor Moon", japanese: "美少女戦士セーラームーン",
                    synopsis: "Usagi Tsukino and her friends discover they are guardians of the cosmos destined to protect the Earth.",
                    status: .finished, score: 8.2, start: (1991, 12, 28), end: (1997, 2, 3), chapters: 60, volumes: 18,
                    cover: "https://cdn.myanimelist.net/images/manga/4/260613l.jpg",
                    genres: [.adventure, .fantasy, .romance], themes: [.mahouShoujo, .school], demographics: [.shoujo],
                    authors: [takeuchi]
                ),
                Self.manga(
                    id: 104, title: "Yotsuba to!", english: "Yotsuba&!", japanese: "よつばと！",
                    synopsis: "Yotsuba discovers the everyday world with boundless curiosity alongside her adoptive father and the neighbours.",
                    status: .publishing, score: 8.88, start: (2003, 3, 21), end: nil, chapters: nil, volumes: 15,
                    cover: "https://cdn.myanimelist.net/images/manga/5/259524l.jpg",
                    genres: [.comedy, .sliceOfLife], themes: [.childcare, .iyashikei], demographics: [.shounen],
                    authors: [azuma]
                ),
                Self.manga(
                    id: 21, title: "Death Note", english: "Death Note", japanese: "デスノート",
                    synopsis: "Light Yagami finds a notebook that kills whoever is written in it and sets out to reshape the world.",
                    status: .finished, score: 8.7, start: (2003, 12, 1), end: (2006, 5, 15), chapters: 108, volumes: 12,
                    cover: "https://cdn.myanimelist.net/images/manga/1/258245l.jpg",
                    genres: [.supernatural, .suspense], themes: [.psychological, .detective], demographics: [.shounen],
                    authors: [ohba, obata]
                ),
                Self.manga(
                    id: 1, title: "Monster", english: "Monster", japanese: "MONSTER",
                    synopsis: "Neurosurgeon Kenzou Tenma saves a boy's life instead of the mayor's, and years later learns the boy has become a killer.",
                    status: .finished, score: 9.15, start: (1994, 12, 5), end: (2001, 12, 20), chapters: 162, volumes: 18,
                    cover: "https://cdn.myanimelist.net/images/manga/3/258224l.jpg",
                    genres: [.awardWinning, .drama, .mystery], themes: [.adultCast, .psychological], demographics: [.seinen],
                    authors: [urasawa]
                ),
            ]
        }

        static func collection(of mangas: [MangaDTO]) -> [UserMangaCollectionDTO] {
            let byID = Dictionary(uniqueKeysWithValues: mangas.map { ($0.id, $0) })
            func entry(_ id: Int, owned: ClosedRange<Int>, reading: Int?, complete: Bool = false) -> UserMangaCollectionDTO {
                guard let manga = byID[id] else {
                    preconditionFailure("Manga \(id) is not in the sample")
                }
                return UserMangaCollectionDTO(
                    id: UUID(), manga: manga, volumesOwned: Array(owned),
                    readingVolume: reading, completeCollection: complete
                )
            }
            return [
                entry(42, owned: 1 ... 10, reading: 7),
                entry(13, owned: 1 ... 60, reading: 58),
                entry(26, owned: 1 ... 20, reading: 15),
                entry(2, owned: 1 ... 30, reading: 22),
                entry(1, owned: 1 ... 18, reading: nil, complete: true),
                entry(21, owned: 1 ... 12, reading: 12, complete: true),
                entry(33327, owned: 1 ... 14, reading: 9, complete: true),
                entry(656, owned: 1 ... 1, reading: 1),
            ]
        }

        private static func author(_ firstName: String, _ lastName: String, _ role: AuthorRole) -> AuthorDTO {
            AuthorDTO(id: UUID(), firstName: firstName, lastName: lastName, role: role)
        }

        private static func manga(
            id: Int, title: String, english: String?, japanese: String?, synopsis: String,
            status: MangaStatus, score: Double, start: (Int, Int, Int)?, end: (Int, Int, Int)?,
            chapters: Int?, volumes: Int?, cover: String?,
            genres: [Genre], themes: [Theme], demographics: [Demographic],
            authors: [AuthorDTO]
        ) -> MangaDTO {
            MangaDTO(
                id: id, title: title, titleEnglish: english, titleJapanese: japanese, synopsis: synopsis,
                background: nil, startDate: start.map(date), endDate: end.map(date),
                score: score, status: status, chapters: chapters, volumes: volumes,
                mainPicture: cover, url: "https://myanimelist.net/manga/\(id)",
                authors: authors,
                genres: genres.map { GenreDTO(id: UUID(), genre: $0.rawValue) },
                themes: themes.map { ThemeDTO(id: UUID(), theme: $0.rawValue) },
                demographics: demographics.map { DemographicDTO(id: UUID(), demographic: $0.rawValue) }
            )
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
