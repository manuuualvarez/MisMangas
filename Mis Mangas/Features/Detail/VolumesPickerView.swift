//
//  VolumesPickerView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftData
import SwiftUI

/// Which volumes the reader owns: a grid of numbered cells, 1 to the published count, each one
/// toggling on tap. While the count is unknown, a number field stands in: `n` means volumes 1…n.
struct VolumesPickerView: View {
    @Bindable var draft: CollectionEditorDraft
    /// Focus of the number field, so the form can put the number pad away.
    var isEditingNumber: FocusState<Bool>.Binding

    /// Cells grow with the text size, so a three-digit number never wraps at accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var cellMinimumWidth = 44.0

    var body: some View {
        if let count = draft.volumesCount, count > 0 {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellMinimumWidth), spacing: 8)], spacing: 8) {
                ForEach(1 ... count, id: \.self) { volume in
                    let isOwned = draft.volumesOwned.contains(volume)
                    Button {
                        draft.toggle(volume: volume)
                    } label: {
                        Text(volume, format: .number)
                            .lineLimit(1)
                    }
                    .buttonStyle(.volumeCell(isSelected: isOwned))
                    .accessibilityLabel("Volume \(volume)")
                    // "Selected" alone says it is owned, as any selectable cell does.
                    .accessibilityAddTraits(isOwned ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Volumes owned")
            .accessibilityValue("^[\(draft.volumesOwned.count) volume](inflect: true) of \(count) owned")
        } else {
            LabeledContent("Volumes owned") {
                TextField("Volumes owned", value: $draft.ownedVolumeCount, format: .number, prompt: Text("None").foregroundStyle(.mmSecondaryLabel))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused(isEditingNumber)
            }
        }
    }
}

// Dragon Ball: 42 published volumes, 1–10 owned.
#Preview("Grid", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @FocusState var isEditingNumber: Bool
    if let manga = mangas.first(where: { $0.id == 42 }) {
        Form { VolumesPickerView(draft: CollectionEditorDraft(from: manga), isEditingNumber: $isEditingNumber) }
    }
}

// Kingdom: still being published, no volume count.
#Preview("Unknown count", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @FocusState var isEditingNumber: Bool
    if let manga = mangas.first(where: { $0.id == 16765 }) {
        Form { VolumesPickerView(draft: CollectionEditorDraft(from: manga), isEditingNumber: $isEditingNumber) }
    }
}
