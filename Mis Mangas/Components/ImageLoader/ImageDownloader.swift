//
//  ImageDownloader.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Downloads cover bytes on `@APIActor` through the shared pipeline (no auth, no JSON headers).
/// `session` is the seam tests replace with the mocked transport.
struct ImageDownloader: NetworkInteractor {
    let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    /// Bytes of the resource at `url`; non-2xx statuses and transport failures surface as `APIError`.
    func data(from url: URL) async throws(APIError) -> Data {
        try await getData(request: URLRequest(url: url))
    }
}
