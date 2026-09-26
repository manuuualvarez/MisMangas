//
//  WatchMangaDetailView.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftData
import SwiftUI

/// One manga being read: cover, title and the volume the reader is on, which the stepper and
/// "Mark next volume read" change on the watch and send to the iPhone. A record handed over by
/// the list stays as it was fetched even after the store changes, so the screen queries it again
/// by id and tells the view model what the store holds, which is how a change from the iPhone
/// shows without leaving the screen.
struct WatchMangaDetailView: View {
    /// The manga the list opened: the identity of the screen and the fallback until the query
    /// answers.
    private let selected: Manga
    @Query private var stored: [Manga]
    @State private var viewModel: WatchReadingViewModel

    init(manga: Manga, dependencies: WatchDependencies) {
        selected = manga
        let id = manga.id
        _stored = Query(filter: #Predicate<Manga> { $0.id == id })
        _viewModel = State(initialValue: WatchReadingViewModel(
            mangaID: manga.id,
            readingVolume: manga.collectionEntry?.readingVolume,
            volumes: manga.volumes,
            syncActor: dependencies.syncActor,
            transport: dependencies.transport
        ))
    }

    private var manga: Manga {
        stored.first ?? selected
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchMangaDetailHeaderView(manga: manga)
                // Above the controls, so it shows without scrolling.
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scenePadding(.minimum, edges: .horizontal)
                }
                Stepper(value: $viewModel.draft, in: viewModel.readingVolumeRange) {
                    Text(manga.readingVolumeText(viewModel.draft))
                        .font(.footnote)
                }
                // One adjustable element for VoiceOver instead of "Remove", the text and "Add".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reading volume")
                .accessibilityValue(manga.readingVolumeAccessibilityValue(viewModel.draft))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    // The view model keeps the draft within the volumes.
                    case .increment:
                        viewModel.draft += 1
                    case .decrement:
                        viewModel.draft -= 1
                    @unknown default:
                        break
                    }
                }
                Button("Mark next volume read") {
                    viewModel.markNextVolumeRead()
                    // Focus stays on the button, away from the progress it just changed.
                    AccessibilityNotification.Announcement(
                        String(localized: "Reading volume \(manga.readingVolumeAccessibilityValue(viewModel.draft))")
                    ).post()
                }
                .accessibilityHint("Moves the reading volume to the next one")
                .disabled(viewModel.isOnLastVolume)
            }
        }
        .containerBackground(.fill.tertiary, for: .navigation)
        .onChange(of: viewModel.draft) {
            viewModel.draftChanged()
        }
        // Initial too: the view model starts from the list's record, which may be older than the
        // query's first answer.
        .onChange(of: manga.collectionEntry?.readingVolume, initial: true) { _, volume in
            viewModel.storedVolumeChanged(volume, volumes: manga.volumes)
        }
        .onChange(of: viewModel.errorMessage) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }
}

// Dragon Ball: reading volume 7 of 42.
#Preview("Reading", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Environment(WatchDependencies.self) var dependencies
    if let manga = mangas.first(where: { $0.id == 42 }) { WatchMangaDetailView(manga: manga, dependencies: dependencies) }
}

// Kingdom: reading volume 5, volume count unknown.
#Preview("Volume count unknown", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Environment(WatchDependencies.self) var dependencies
    if let manga = mangas.first(where: { $0.id == 16765 }) { WatchMangaDetailView(manga: manga, dependencies: dependencies) }
}

// Death Note: on the last volume, 12 of 12.
#Preview("Last volume", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Environment(WatchDependencies.self) var dependencies
    if let manga = mangas.first(where: { $0.id == 21 }) { WatchMangaDetailView(manga: manga, dependencies: dependencies) }
}
