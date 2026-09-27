//
//  CollectionEditorSheet.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftData
import SwiftUI

/// The collection form of a manga, presented as a sheet with its own navigation bar: the volumes
/// owned, the reading volume (a stepper within the published count, a free number field while
/// the count is unknown), the complete switch and, for a manga already in the collection, its
/// removal after confirmation. Edits live on a draft until "Save" writes them to the store. Without
/// a session, a footer says the changes stay on the device until the user signs in.
struct CollectionEditorSheet: View {
    let manga: Manga
    @State private var viewModel: CollectionViewModel
    @State private var draft: CollectionEditorDraft
    @State private var isConfirmingRemoval = false
    /// The number pad has no key to put it away: the keyboard toolbar offers "Done".
    @FocusState private var isEditingNumber: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(manga: Manga, dependencies: AppDependencies) {
        self.manga = manga
        _viewModel = State(initialValue: dependencies.makeCollectionViewModel(presentsRejections: false))
        _draft = State(initialValue: CollectionEditorDraft(from: manga))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VolumesPickerView(draft: draft, isEditingNumber: $isEditingNumber)
                        // The form keeps the row's first height: when the text grows with the sheet
                        // open, the grid gains rows and the last ones fell outside it.
                        .id(dynamicTypeSize)
                } header: {
                    // The system gray of headers and footers falls below 4.5:1 on the grouped background.
                    Text("Volumes owned")
                        .foregroundStyle(.mmSecondaryLabel)
                } footer: {
                    if (draft.volumesCount ?? 0) == 0 {
                        Text("How many volumes you own, counted from the first one.")
                            .foregroundStyle(.mmSecondaryLabel)
                    }
                }
                Section {
                    if let count = draft.volumesCount, count > 0 {
                        Stepper(value: $draft.readingVolumeSelection, in: 0 ... count) {
                            ReadingVolumeLabel(readingVolume: draft.readingVolume)
                        }
                        // A stepper builds its accessible name from every text in its label, the
                        // value included, so VoiceOver read the value twice: it gets a plain one.
                        .accessibilityRepresentation {
                            Stepper("Reading volume", value: $draft.readingVolumeSelection, in: 0 ... count)
                                .accessibilityValue(draft.readingVolume.map { $0.formatted() } ?? String(localized: "Not started"))
                        }
                    } else {
                        LabeledContent("Reading volume") {
                            TextField("Reading volume", value: $draft.readingVolume, format: .number, prompt: Text("Not started").foregroundStyle(.mmSecondaryLabel))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($isEditingNumber)
                        }
                    }
                } header: {
                    Text("Reading")
                        .foregroundStyle(.mmSecondaryLabel)
                }
                Section {
                    Toggle("Complete collection", isOn: $draft.completeCollection)
                        .accessibilityHint((draft.volumesCount ?? 0) > 0 ? Text("Marks every volume as owned") : Text(verbatim: ""))
                } footer: {
                    // Without an account nothing leaves the device; say it before saving, since the
                    // sheet closes once the change is saved.
                    if !viewModel.isSyncAvailable {
                        Text("Changes are saved on this device. Sign in to sync.")
                            .foregroundStyle(.mmSecondaryLabel)
                    }
                }
                if let error = viewModel.error {
                    Section {
                        InlineErrorView(error: error) {
                            Task { await save() }
                        }
                    }
                }
                if manga.inCollection {
                    Section {
                        Button("Remove from collection", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                        // The system red falls below 4.5:1 on a light row.
                        .foregroundStyle(.mmDestructive)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(manga.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Symbols, not words: the text stays as the accessible name of each button.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        Task { await save() }
                    }
                    .disabled(viewModel.isSaving)
                    // The confirming button is filled: the fill accent keeps its symbol legible.
                    .tint(.mmAccentFill)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditingNumber = false }
                }
            }
            .confirmationDialog("Remove from collection?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    Task { await remove() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your volumes and reading progress for this manga will be deleted.")
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.isSaving)
    }

    private func save() async {
        let values = draft.validated()
        await viewModel.save(
            mangaID: manga.id,
            volumesOwned: values.volumesOwned,
            readingVolume: values.readingVolume,
            completeCollection: values.completeCollection
        )
        finish(announcing: String(localized: "Saved"))
    }

    private func remove() async {
        await viewModel.remove(mangaID: manga.id)
        finish(announcing: String(localized: "\(manga.title) removed from collection"))
    }

    /// Closes the sheet after a write that succeeded, saying so. A failure is announced on every
    /// attempt, even when a retry fails with the same error: the error row appears below the fold.
    private func finish(announcing confirmation: String) {
        if let description = viewModel.error?.errorDescription {
            AccessibilityNotification.Announcement(description).post()
        } else {
            // High priority: the focus moving back from the closing sheet would cut it short.
            var announcement = AttributedString(confirmation)
            announcement.accessibilitySpeechAnnouncementPriority = .high
            AccessibilityNotification.Announcement(announcement).post()
            dismiss()
        }
    }
}

// Dr. Slump: 18 volumes, not in the collection yet.
#Preview("New entry", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Environment(AppDependencies.self) var dependencies
    if let manga = mangas.first(where: { $0.id == 796 }) {
        CollectionEditorSheet(manga: manga, dependencies: dependencies)
    }
}

// Dragon Ball: volumes 1–10 owned, reading volume 7.
#Preview("Existing entry", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Environment(AppDependencies.self) var dependencies
    if let manga = mangas.first(where: { $0.id == 42 }) {
        CollectionEditorSheet(manga: manga, dependencies: dependencies)
    }
}

// Kingdom: still being published, no volume count.
#Preview("Unknown volume count", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Environment(AppDependencies.self) var dependencies
    if let manga = mangas.first(where: { $0.id == 16765 }) {
        CollectionEditorSheet(manga: manga, dependencies: dependencies)
    }
}
