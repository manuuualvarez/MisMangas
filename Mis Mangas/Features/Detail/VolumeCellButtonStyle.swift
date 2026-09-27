//
//  VolumeCellButtonStyle.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftUI

/// A numbered cell of the volume grid: filled with the accent and set in bold when the volume is
/// owned, on the tertiary system fill otherwise, so the state never rests on color alone and the
/// number on the accent reads as large text. Both fills keep the hit target at 44 pt.
struct VolumeCellButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.monospacedDigit())
            .fontWeight(isSelected ? .bold : .regular)
            .frame(maxWidth: .infinity, minHeight: 44)
            // A ternary gives the compiler no member to infer against, so the colors are spelled out.
            .foregroundStyle(isSelected ? Color.mmOnAccent : Color.primary)
            .background(isSelected ? Color.mmAccentFill : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            // The accent fill alone sits close to the unowned fill in dark mode: an owned cell also
            // carries an outline in the label color, which stands out in every appearance.
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary, lineWidth: isSelected ? 2 : 0)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == VolumeCellButtonStyle {
    static func volumeCell(isSelected: Bool) -> VolumeCellButtonStyle {
        VolumeCellButtonStyle(isSelected: isSelected)
    }
}
