//
//  APIActor.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// Global actor that isolates the whole networking layer.
/// `NetworkInteractor`, its extension defaults and every repository run here, so a conformer
/// is implicitly `Sendable` and never needs a separate client or interceptor.
@globalActor
actor APIActor {
    static let shared = APIActor()
}
