//
//  StatisticLabeledContentStyle.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftUI

/// A statistic cell: small uppercase label over a bold value, leading aligned.
struct StatisticLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            configuration.label
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.mmSecondaryLabel)
            configuration.content
                .font(.title3.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension LabeledContentStyle where Self == StatisticLabeledContentStyle {
    static var statistic: StatisticLabeledContentStyle { StatisticLabeledContentStyle() }
}

#Preview("Statistic") {
    LabeledContent("Volumes") { Text(42, format: .number) }
        .labeledContentStyle(.statistic)
        .padding()
}
