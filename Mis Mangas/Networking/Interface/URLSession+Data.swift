//
//  URLSession+Data.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

extension URLSession {
    /// Performs the request, narrows the response to `HTTPURLResponse` and translates every
    /// framework error into a typed `APIError`. Status codes are left to the caller.
    func getData(for request: URLRequest,
                 delegate: (any URLSessionTaskDelegate)? = nil) async throws(APIError) -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await data(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.unknown
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch {
            throw .transport(error)
        }
    }
}
