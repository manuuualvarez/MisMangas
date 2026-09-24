//
//  ReadingVolumeLabel.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// The label of the reading volume stepper: the name on the leading side and the volume, or
/// "Not started", on the trailing side. At accessibility sizes the value goes under the name:
/// side by side, next to the stepper's buttons, both break mid-word.
struct ReadingVolumeLabel: View {
    let readingVolume: Int?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
        layout {
            Text("Reading volume")
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            Group {
                if let readingVolume {
                    Text(readingVolume, format: .number)
                } else {
                    Text("Not started")
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Reading", traits: .sampleData) {
    Form { ReadingVolumeLabel(readingVolume: 7) }
}

#Preview("Not started", traits: .sampleData) {
    Form { ReadingVolumeLabel(readingVolume: nil) }
}
