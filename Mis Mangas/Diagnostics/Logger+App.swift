//
//  Logger+App.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import OSLog

/// The app's loggers: one subsystem shared by the app, the watch app and the widget, and one
/// category per layer that logs, so Console and Instruments filter by either. A category is
/// added the day its layer emits its first log. Nothing sensitive is ever logged: tokens and
/// credentials stay out, and user identifiers travel as `.private`.
extension Logger {
    /// The subsystem of every log and signpost the three targets emit.
    static let subsystem = "cloud.manuelalvarez.Mis-Mangas"

    static let widget = Logger(subsystem: subsystem, category: "widget")
}
