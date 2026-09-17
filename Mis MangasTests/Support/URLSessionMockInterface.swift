//
//  URLSessionMockInterface.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// `URLProtocol` that replaces the transport in every networking test.
///
/// Routing: the request is matched by `(httpMethod, path segments)` onto a
/// `CatalogMockScenario.Key`, recorded (hit counter + captured request + drained body), and
/// answered with the behavior the test configured. Only two hosts are served — the API host
/// of the backend and the cover CDN found in the fixtures; any other host is a
/// `preconditionFailure`, because a test must never reach a real backend.
///
/// The hosts are literals owned by the test target on purpose: they are the oracle for the
/// production `urlBase`, not a copy of it.
final class URLSessionMockInterface: URLProtocol {
    /// Host of the backend.
    static let apiHost = "mymanga-acacademy-5607149ebe3d.herokuapp.com"
    /// Host every `mainPicture` in the fixtures points to.
    static let imageHost = "cdn.myanimelist.net"

    /// Base URL of the API as the tests know it (independent of the production literal).
    static let apiBase: URL = {
        guard let url = URL(string: "https://\(apiHost)") else {
            preconditionFailure("Invalid API base literal in URLSessionMockInterface")
        }
        return url
    }()

    /// The injection seam: an ephemeral session whose only protocol is this mock.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLSessionMockInterface.self]
        return URLSession(configuration: configuration)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            fail(URLError(.badURL))
            return
        }
        let method = request.httpMethod ?? "GET"
        let key = Self.route(method: method, url: url)
        CatalogMockScenario.record(key, request: request, body: request.bodyData)
        apply(CatalogMockScenario.behavior(for: key), to: url)
    }

    override func stopLoading() {}

    // MARK: - Routing

    private static func route(method: String, url: URL) -> CatalogMockScenario.Key {
        let host = url.host() ?? "<no host>"
        switch host {
        case imageHost:
            return .image
        case apiHost:
            break
        default:
            preconditionFailure(
                "URLSessionMockInterface: unmocked host \"\(host)\" for \(method) \(url.absoluteString). " +
                "Tests never reach a real backend; only \(apiHost) and \(imageHost) are served."
            )
        }

        let segments = url.pathComponents.filter { $0 != "/" }
        switch (method, segments) {
        case ("GET", ["list", "mangas"]): return .listMangas
        case ("GET", ["list", "bestMangas"]): return .listBestMangas
        case ("GET", ["list", "genres"]): return .listGenres
        case ("GET", ["list", "themes"]): return .listThemes
        case ("GET", ["list", "demographics"]): return .listDemographics
        case ("GET", ["list", "authorsPaged"]): return .listAuthorsPaged
        case ("POST", ["list", "authorsByIds"]): return .authorsByIds
        case ("POST", ["search", "manga"]): return .customSearch
        default: break
        }

        guard segments.count == 3 else {
            return .unmatched
        }
        switch (method, segments[0], segments[1]) {
        case ("GET", "list", "mangaByGenre"): return .mangaByGenre
        case ("GET", "list", "mangaByTheme"): return .mangaByTheme
        case ("GET", "list", "mangaByDemographic"): return .mangaByDemographic
        case ("GET", "list", "mangaByAuthor"): return .mangaByAuthor
        case ("GET", "search", "manga"): return .mangaByID
        case ("GET", "search", "mangasBeginsWith"): return .mangasBeginsWith
        case ("GET", "search", "mangasContains"): return .mangasContains
        case ("GET", "search", "author"): return .searchAuthor
        default: return .unmatched
        }
    }

    // MARK: - Behaviors

    private func apply(_ behavior: CatalogMockScenario.Behavior, to url: URL) {
        switch behavior {
        case .fixture(let fileName):
            // Fixture loading is the one place allowed to fail loudly.
            do {
                respond(status: 200, body: try TestFixtures.data(fileName), contentType: "application/json; charset=utf-8", to: url)
            } catch {
                preconditionFailure("URLSessionMockInterface: fixture \(fileName) could not be loaded: \(error)")
            }
        case .json(let text, let status):
            respond(status: status, body: Data(text.utf8), contentType: "application/json; charset=utf-8", to: url)
        case .data(let data, let status):
            respond(status: status, body: data, contentType: "application/octet-stream", to: url)
        case .status(let status):
            respond(status: status, body: Data(), contentType: "application/json; charset=utf-8", to: url)
        case .transportError(let code):
            fail(URLError(code))
        case .delayed(let duration, let then):
            // `startLoading` runs on the single `com.apple.CFNetwork.CustomProtocols` thread (verified
            // empirically), so sleeping here serializes every mock response, which is what "in flight"
            // means for the tests. Keep durations short. Cancelling the awaiting task is not blocked by
            // this sleep: `URLSession` resumes the continuation with `URLError.cancelled` immediately.
            Thread.sleep(forTimeInterval: Self.timeInterval(duration))
            apply(then, to: url)
        }
    }

    private static func timeInterval(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }

    // MARK: - Delivery

    private func respond(status: Int, body: Data, contentType: String, to url: URL) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        ) else {
            fail(URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func fail(_ error: URLError) {
        client?.urlProtocol(self, didFailWithError: error)
    }
}
