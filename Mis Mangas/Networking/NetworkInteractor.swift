//
//  NetworkInteractor.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Networking base protocol. Every repository conforms and inherits the pipeline
/// request → transport → status mapping → decode. `session` is the seam tests replace with a
/// `URLSession` whose transport is `URLSessionMockInterface`.
@APIActor
protocol NetworkInteractor {
    var session: URLSession { get }
}

extension NetworkInteractor {
    var session: URLSession { .shared }

    /// Sends the request and returns the body when the status is inside `accepting`.
    /// Mapping: 401 → `.unauthorized`, 403 → `.forbidden`, 404 → `.notFound`,
    /// 5xx → `.serverError`, any other status outside `accepting` → `.http(status:body:)`.
    func getData(request: URLRequest,
                 accepting: Range<Int> = 200..<300) async throws(APIError) -> Data {
        let (data, response) = try await session.getData(for: request)
        guard accepting.contains(response.statusCode) else {
            switch response.statusCode {
            case 401: throw .unauthorized
            case 403: throw .forbidden
            case 404: throw .notFound
            case 500..<600: throw .serverError
            default: throw .http(status: response.statusCode, body: data)
            }
        }
        return data
    }

    /// `getData` + `JSONDecoder.app`. A 2xx body that does not decode becomes `.decoding`.
    func getJSON<JSON: Decodable>(request: URLRequest, type: JSON.Type) async throws(APIError) -> JSON {
        let data = try await getData(request: request)
        do {
            return try JSONDecoder.app.decode(type, from: data)
        } catch {
            throw .decoding(error)
        }
    }

    /// For endpoints whose body is irrelevant: verifies the status only (any 2xx by default).
    func getStatus(request: URLRequest, accepting: Range<Int> = 200..<300) async throws(APIError) {
        _ = try await getData(request: request, accepting: accepting)
    }
}
