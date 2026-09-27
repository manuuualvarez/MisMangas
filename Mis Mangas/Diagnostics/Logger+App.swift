//
//  Logger+App.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import OSLog

/// The app's loggers: one subsystem shared by the app, the watch app and the widget, and one
/// category per layer, so Console and Instruments filter by either. Nothing sensitive is ever
/// logged: tokens and credentials stay out, and user identifiers travel as `.private`.
extension Logger {
    /// The subsystem of every log and signpost the three targets emit.
    static let subsystem = "cloud.manuelalvarez.Mis-Mangas"

    static let networking = Logger(subsystem: subsystem, category: "networking")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let widget = Logger(subsystem: subsystem, category: "widget")
    static let watch = Logger(subsystem: subsystem, category: "watch")
}
