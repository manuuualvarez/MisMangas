//
//  Text+CatalogTotal.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

extension Text {
    /// The subtitle under a catalog title: the server total once it arrives, a dash when the
    /// load failed before one did, and "Loading…" meanwhile. Never empty: the large title bar
    /// sizes itself on the first layout and does not grow when a subtitle appears later.
    static func catalogTotal(_ total: Int?, isFailed: Bool) -> Text {
        if let total {
            Text("^[\(total) manga](inflect: true)")
        } else if isFailed {
            // A dash on screen; words for VoiceOver, which would otherwise skip or misname it.
            Text(verbatim: "—")
                .accessibilityLabel("Total unavailable")
        } else {
            Text("Loading…")
        }
    }
}
