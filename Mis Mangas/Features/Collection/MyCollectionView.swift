//
//  MyCollectionView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftData
import SwiftUI

/// The My Collection tab: every manga in the collection, read from the store, with a summary,
/// a filter (All / Reading / Complete), an order and a list or grid layout chosen from the
/// toolbar menu. A two-column split view like the catalog: the selected manga fills the detail
/// column on iPad and is pushed on iPhone. An empty collection offers a way to the catalog, and
/// a chip in the detail applies its category there. With a session, the list syncs with a pull or
/// the toolbar's sync button (which counts the pending changes), stays current whenever a pass
/// ends, and says in an alert when the server refused changes or the device could not sync. A link
/// to a manga selects it, brought from the server first when the device does not hold it, saying it
/// is opening meanwhile.
struct MyCollectionView: View {
    @Query(filter: #Predicate<Manga> { $0.inCollection == true }, sort: \Manga.title)
    private var mangas: [Manga]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selectedTab: AppTab
    @Binding var pendingCatalogMode: CatalogMode?
    @Binding var pendingMangaID: Int?
    @State private var viewModel: CollectionViewModel
    @State private var filter: CollectionFilter
    @State private var sort = CollectionSort.title
    @State private var selectedManga: Manga?
    /// Which column shows when the split view collapses into one: a grid cell selects with a
    /// button, and only a list selection makes the collapsed split view push the detail on
    /// its own.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @AppStorage("collection.displayMode") private var displayMode: DisplayMode = .list
    @Namespace private var heroNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        dependencies: AppDependencies,
        selectedTab: Binding<AppTab>,
        pendingCatalogMode: Binding<CatalogMode?>,
        pendingMangaID: Binding<Int?>,
        filter: CollectionFilter = .all
    ) {
        _selectedTab = selectedTab
        _pendingCatalogMode = pendingCatalogMode
        _pendingMangaID = pendingMangaID
        _viewModel = State(initialValue: dependencies.makeCollectionViewModel(presentsRejections: true))
        _filter = State(initialValue: filter)
    }

    var body: some View {
        // Filtered and sorted in memory: a collection holds hundreds of series at most, well
        // within what one pass per update handles.
        let visibleMangas = mangas.filtered(by: filter).sorted(by: sort)
        // The summary counts the whole collection, whatever the filter shows.
        let stats = CollectionStats(mangas: mangas)
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            Group {
                if mangas.isEmpty {
                    ContentUnavailableView {
                        Label("Your collection is empty", systemImage: "books.vertical")
                    } description: {
                        Text("Add a manga from its page in the catalog.")
                    } actions: {
                        Button("Browse catalog") {
                            selectedTab = .catalog
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mmAccentFill)
                        .controlSize(.large)
                    }
                } else if visibleMangas.isEmpty {
                    ContentUnavailableView {
                        Label("No mangas match", systemImage: "line.3.horizontal.decrease")
                    } description: {
                        Text("No manga in your collection matches this filter.")
                    } actions: {
                        // The default style of this view is a bare link about 18 pt tall.
                        Button("Show all") {
                            filter = .all
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mmAccentFill)
                        .controlSize(.large)
                    }
                } else {
                    switch displayMode {
                    case .list:
                        CollectionListView(
                            mangas: visibleMangas,
                            stats: stats,
                            selection: $selectedManga,
                            viewModel: viewModel,
                            namespace: heroNamespace
                        )
                    case .grid:
                        CollectionGridView(
                            mangas: visibleMangas,
                            stats: stats,
                            selection: $selectedManga,
                            namespace: heroNamespace
                        )
                    }
                }
            }
            // Only the list column: the detail, opened with a zoom, keeps its own gestures.
            .refreshable {
                await viewModel.synchronize()
            }
            .task {
                await viewModel.observePasses()
            }
            // Content, not a sidebar: the tab bar already is the app's sidebar.
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle("My Collection")
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                if viewModel.isSyncAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        CollectionSyncButton(pendingCount: viewModel.pendingCount) {
                            Task {
                                await viewModel.synchronize()
                                if let announcement = viewModel.syncAnnouncement {
                                    AccessibilityNotification.Announcement(announcement).post()
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(CollectionFilter.allCases, id: \.self) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        Picker("Sort by", selection: $sort) {
                            ForEach(CollectionSort.allCases, id: \.self) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        Picker("Layout", selection: $displayMode) {
                            Label("Grid", systemImage: DisplayMode.grid.systemImage).tag(DisplayMode.grid)
                            Label("List", systemImage: DisplayMode.list.systemImage).tag(DisplayMode.list)
                        }
                    } label: {
                        Label("Options", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityValue(Text("\(filter.title), sorted by \(sort.title), \(displayMode.title)"))
                    .accessibilityHint("Filters, sorts or changes the layout of the collection")
                }
            }
            .alert(
                "Changes rejected",
                isPresented: $viewModel.isRejectionNoticePresented,
                presenting: viewModel.rejectedMangaIDs.count
            ) { _ in
                Button("OK") {
                    Task { await viewModel.acknowledgeRejections() }
                }
            } message: { count in
                Text("^[\(count) change](inflect: true) couldn't be saved on the server, which kept its own version.")
            }
            .alert(
                "Couldn't sync",
                isPresented: $viewModel.isSyncErrorPresented,
                presenting: viewModel.syncError
            ) { _ in
                Button("OK") {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 520, max: 720)
        } detail: {
            if let selectedManga {
                MangaDetailView(manga: selectedManga)
                    // With Reduce Motion the detail fades in instead of growing out of its cover.
                    .navigationTransition(
                        reduceMotion
                            ? AnyNavigationTransition(.crossFade)
                            : AnyNavigationTransition(.zoom(sourceID: selectedManga.id, in: heroNamespace))
                    )
            } else {
                ContentUnavailableView("Select a manga", systemImage: "book.closed")
            }
        }
        .navigationSplitViewStyle(.balanced)
        // On the split view and not the list: a link can arrive while the pushed detail hides the list.
        .alert(
            "Couldn't open manga",
            isPresented: $viewModel.isDeepLinkErrorPresented,
            presenting: viewModel.deepLinkError
        ) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .overlay {
            if viewModel.isOpeningDeepLink {
                ProgressView("Opening…")
                    // The default secondary label measured 4.2:1 over the material.
                    .foregroundStyle(.primary)
                    .padding()
                    // Spelled with the type on purpose: as an implicit member inside a background
                    // with a shape, the color crashed the app at launch.
                    .background(
                        reduceTransparency ? AnyShapeStyle(Color.mmSurface) : AnyShapeStyle(.regularMaterial),
                        in: .rect(cornerRadius: 12)
                    )
            }
        }
        // The overlay takes no focus: say that the wait began.
        .onChange(of: viewModel.isOpeningDeepLink) { _, isOpening in
            if isOpening {
                AccessibilityNotification.Announcement(String(localized: "Opening…")).post()
            }
        }
        .task(id: pendingMangaID) {
            guard let mangaID = pendingMangaID else {
                return
            }
            let isReady = await viewModel.prepareDeepLinkedManga(id: mangaID)
            // A newer link replaced this one, or the tab went away: the link still waits.
            guard !Task.isCancelled else {
                return
            }
            if isReady {
                var descriptor = FetchDescriptor<Manga>(predicate: #Predicate { $0.id == mangaID })
                descriptor.fetchLimit = 1
                // Unreadable right after being stored: the selection stays as it was.
                if let manga = try? modelContext.fetch(descriptor).first {
                    selectedManga = manga
                    // Where the detail fills a column, focus stays on the list: say what opened.
                    // Low priority is queued behind the speech in progress instead of interrupting it.
                    var announcement = AttributedString(localized: "Opened \(manga.title)")
                    announcement.accessibilitySpeechAnnouncementPriority = .low
                    AccessibilityNotification.Announcement(announcement).post()
                }
            }
            pendingMangaID = nil
        }
        .environment(
            \.applyCatalogMode,
            CollectionModeApplier(
                selectedTab: $selectedTab,
                pendingCatalogMode: $pendingCatalogMode,
                selectedManga: $selectedManga
            )
        )
        // Collapsed, the detail shows whenever a manga is selected, whether a list row or a
        // grid cell selected it; going back deselects it, so the same cell opens it again.
        .onChange(of: selectedManga) { _, manga in
            compactColumn = manga == nil ? .sidebar : .detail
        }
        .onChange(of: compactColumn) { _, column in
            if column == .sidebar {
                selectedManga = nil
            }
        }
        // Focus goes back to the menu, which only names the filter: say what it left on screen.
        .onChange(of: filter) { _, newFilter in
            AccessibilityNotification.Announcement(mangas.filterAnnouncement(for: newFilter)).post()
        }
    }
}

#Preview("Collection", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var selectedTab = AppTab.collection
    @Previewable @State var pendingMode: CatalogMode?
    @Previewable @State var pendingMangaID: Int?
    MyCollectionView(dependencies: dependencies, selectedTab: $selectedTab, pendingCatalogMode: $pendingMode, pendingMangaID: $pendingMangaID)
}

#Preview("Reading", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var selectedTab = AppTab.collection
    @Previewable @State var pendingMode: CatalogMode?
    @Previewable @State var pendingMangaID: Int?
    MyCollectionView(
        dependencies: dependencies,
        selectedTab: $selectedTab,
        pendingCatalogMode: $pendingMode,
        pendingMangaID: $pendingMangaID,
        filter: .reading
    )
}

#Preview("Empty", traits: .emptyStore()) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var selectedTab = AppTab.collection
    @Previewable @State var pendingMode: CatalogMode?
    @Previewable @State var pendingMangaID: Int?
    MyCollectionView(dependencies: dependencies, selectedTab: $selectedTab, pendingCatalogMode: $pendingMode, pendingMangaID: $pendingMangaID)
}

#Preview("Link", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var selectedTab = AppTab.collection
    @Previewable @State var pendingMode: CatalogMode?
    @Previewable @State var pendingMangaID = SampleData.collection.first?.manga.id
    MyCollectionView(dependencies: dependencies, selectedTab: $selectedTab, pendingCatalogMode: $pendingMode, pendingMangaID: $pendingMangaID)
}
