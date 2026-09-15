//
//  CatalogModePickerView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Segmented All / Best switch under the catalog title.
struct CatalogModePickerView: View {
    @Binding var selection: CatalogMode

    var body: some View {
        Picker("Mode", selection: $selection) {
            Text("All").tag(CatalogMode.all)
            Text("Best").tag(CatalogMode.best)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

#Preview("Picker", traits: .sampleData) {
    @Previewable @State var selection = CatalogMode.all
    CatalogModePickerView(selection: $selection)
}
