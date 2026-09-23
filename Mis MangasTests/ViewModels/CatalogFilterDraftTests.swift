//
//  CatalogFilterDraftTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 17/09/2026.
//

@testable import Mis_Mangas
import Testing

/// The filter form's draft: one category at a time (the `/list/mangaBy…` endpoints filter by a
/// single one) and "Any" clears a filter without touching the All / Best listing.
@Suite("CatalogFilterDraft")
struct CatalogFilterDraftTests {
    @Test(arguments: [
        (CatalogMode.byGenre("Romance"), "Romance", nil, nil),
        (CatalogMode.byTheme("Martial Arts"), nil, "Martial Arts", nil),
        (CatalogMode.byDemographic("Shounen"), nil, nil, "Shounen"),
        (CatalogMode.all, nil, nil, nil),
        (CatalogMode.best, nil, nil, nil),
        (CatalogMode.titleContains("ball"), nil, nil, nil),
    ] as [(CatalogMode, String?, String?, String?)])
    func `The draft opens on the category of the current mode`(
        mode: CatalogMode, genre: String?, theme: String?, demographic: String?
    ) {
        let draft = CatalogFilterDraft(mode: mode)

        #expect(draft.genre == genre)
        #expect(draft.theme == theme)
        #expect(draft.demographic == demographic)
    }

    @Test func `Choosing one category returns the other two to Any`() {
        var draft = CatalogFilterDraft(mode: .byGenre("Romance"))

        draft.theme = "Martial Arts"
        #expect(draft.genre == nil)
        #expect(draft.theme == "Martial Arts")

        draft.demographic = "Seinen"
        #expect(draft.theme == nil)
        #expect(draft.demographic == "Seinen")

        draft.genre = "Action"
        #expect(draft.demographic == nil)
        #expect(draft.genre == "Action")
    }

    @Test func `Setting a picker to Any leaves the other pickers alone`() {
        var draft = CatalogFilterDraft(mode: .byTheme("Gore"))

        draft.genre = nil
        draft.demographic = nil

        #expect(draft.theme == "Gore")
    }

    @Test(arguments: [
        (CatalogMode.all, CatalogMode.byGenre("Romance")),
        (CatalogMode.best, CatalogMode.byGenre("Romance")),
        (CatalogMode.byTheme("Gore"), CatalogMode.byGenre("Romance")),
    ] as [(CatalogMode, CatalogMode)])
    func `Applying a chosen category filters the catalog by it`(current: CatalogMode, expected: CatalogMode) {
        var draft = CatalogFilterDraft(mode: current)
        draft.genre = "Romance"

        #expect(draft.applied(to: current) == expected)
    }

    @Test(arguments: [
        (CatalogMode.byGenre("Romance"), CatalogMode.all),
        (CatalogMode.byDemographic("Kids"), CatalogMode.all),
        (CatalogMode.all, CatalogMode.all),
        (CatalogMode.best, CatalogMode.best),
    ] as [(CatalogMode, CatalogMode)])
    func `Applying Any clears a filter and keeps the All or Best listing`(current: CatalogMode, expected: CatalogMode) {
        var draft = CatalogFilterDraft(mode: current)
        draft.genre = nil
        draft.theme = nil
        draft.demographic = nil

        #expect(draft.applied(to: current) == expected)
    }
}
