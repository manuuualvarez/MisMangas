//
//  OSSignposter+App.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import OSLog

/// The app's performance signposts, under the same subsystem as its loggers. Instruments shows
/// them as named intervals (os_signpost instrument) so a flow can be timed on its own.
extension OSSignposter {
    static let app = OSSignposter(subsystem: Logger.subsystem, category: "performance")
}

/// The intervals the app measures. A name is used at both ends of its interval, so the ends
/// always match: from launch to the first screen, one catalog page, one detail opening, one
/// synchronization pass and one widget timeline.
enum SignpostName {
    static let launch: StaticString = "app.launch"
    static let catalogPage: StaticString = "catalog.page"
    static let detailOpen: StaticString = "detail.open"
    static let syncCollection: StaticString = "sync.collection"
    static let widgetTimeline: StaticString = "widget.timeline"
}
