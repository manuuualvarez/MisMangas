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
/// removal after confirmation. Edits live on a draft until "Save" writes them to the store.
struct CollectionEditorSheet: View {
    let manga: Manga
    @State private var viewModel: CollectionViewModel
    @State private var draft: CollectionEditorDraft
    @State private var isConfirmingRemoval = false
    /// The number pad has no key to put it away: the keyboard toolbar offers "Done".
    @FocusState private var isEditingNumber: Bool
    @Environment(\.dismiss) private var dismiss

    init(manga: Manga, syncService: MangaSyncService) {
        self.manga = manga
        _viewModel = State(initialValue: CollectionViewModel(syncService: syncService))
        _draft = State(initialValue: CollectionEditorDraft(from: manga))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VolumesPickerView(draft: draft, isEditingNumber: $isEditingNumber)
                } header: {
                    Text("Volumes owned")
                } footer: {
                    if (draft.volumesCount ?? 0) == 0 {
                        Text("How many volumes you own, counted from the first one.")
                    }
                }
                Section("Reading") {
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
                            TextField("Reading volume", value: $draft.readingVolume, format: .number, prompt: Text("Not started"))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($isEditingNumber)
                        }
                    }
                }
                Section {
                    Toggle("Complete collection", isOn: $draft.completeCollection)
                        .accessibilityHint((draft.volumesCount ?? 0) > 0 ? Text("Marks every volume as owned") : Text(verbatim: ""))
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
        finish()
    }

    private func remove() async {
        await viewModel.remove(mangaID: manga.id)
        finish()
    }

    /// Closes the sheet after a write that succeeded. A failure is announced on every attempt,
    /// even when a retry fails with the same error: the error row appears below the fold.
    private func finish() {
        if let description = viewModel.error?.errorDescription {
            AccessibilityNotification.Announcement(description).post()
        } else {
            dismiss()
        }
    }
}

// Dr. Slump: 18 volumes, not in the collection yet.
#Preview("New entry", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Environment(AppDependencies.self) var dependencies
    if let manga = mangas.first(where: { $0.id == 796 }) {
        CollectionEditorSheet(manga: manga, syncService: dependencies.syncService)
    }
}

// Dragon Ball: volumes 1–10 owned, reading volume 7.
#Preview("Existing entry", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Environment(AppDependencies.self) var dependencies
    if let manga = mangas.first(where: { $0.id == 42 }) {
        CollectionEditorSheet(manga: manga, syncService: dependencies.syncService)
    }
}

// Kingdom: still being published, no volume count.
#Preview("Unknown volume count", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Environment(AppDependencies.self) var dependencies
    if let manga = mangas.first(where: { $0.id == 16765 }) {
        CollectionEditorSheet(manga: manga, syncService: dependencies.syncService)
    }
}
