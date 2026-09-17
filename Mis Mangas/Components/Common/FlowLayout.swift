//
//  FlowLayout.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// Places subviews left to right at their natural size and wraps to a new row when the next one
/// no longer fits, like words in a paragraph. Meant for chips of varying width; grids of uniform
/// cells keep using `LazyVGrid`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let rows = rows(of: subviews, fitting: available ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.reduce(0) { max($0, $1.width) }
        return CGSize(width: available ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, fitting: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Greedy line breaking: a subview joins the current row if it fits, otherwise it opens the
    /// next one. Every subview is measured against the row width, so one that cannot fit on a
    /// line of its own (a long chip at accessibility text sizes) wraps its text instead of
    /// overflowing the trailing edge.
    private func rows(of subviews: Subviews, fitting maxWidth: CGFloat) -> [Row] {
        let rowProposal = ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil)
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(rowProposal)
            let widthIfAppended = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if widthIfAppended > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append((index, size))
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

#Preview("Chips", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    FlowLayout(spacing: 6) {
        ForEach(mangas.flatMap(\.genres), id: \.self) { name in
            Button(name) {}
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
    .padding()
}

// Every theme the API knows, including the long ones that must wrap at accessibility sizes.
#Preview("Long chips") {
    FlowLayout(spacing: 6) {
        ForEach(Theme.allCases.filter { $0 != .unknown }, id: \.self) { theme in
            Button(theme.rawValue) {}
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
    .padding()
}
