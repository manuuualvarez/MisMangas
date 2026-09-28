//
//  APIErrorTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

@testable import Mis_Mangas
import Testing

private struct DummyError: Error {}

@Suite("APIError")
struct APIErrorTests {
    // MARK: - HTTP status categories

    @Test(arguments: [400, 404])
    func `HTTP 4xx is a client error and not retryable`(status: Int) {
        let error = APIError.http(status: status, body: nil)
        #expect(error.isServerError == false)
        #expect(error.isRetryable == false)
    }

    @Test(arguments: [500, 503])
    func `HTTP 5xx is a server error and retryable`(status: Int) {
        let error = APIError.http(status: status, body: nil)
        #expect(error.isServerError == true)
        #expect(error.isRetryable == true)
    }

    // MARK: - Semantic cases

    @Test(arguments: [APIError.unauthorized, .forbidden, .notFound])
    func `Semantic 4xx cases are client errors only`(error: APIError) {
        #expect(error.isServerError == false)
        #expect(error.isRetryable == false)
    }

    @Test(arguments: [APIError.serverError, .transport(DummyError())])
    func `Server and transport failures are retryable`(error: APIError) {
        #expect(error.isRetryable == true)
    }

    @Test func `serverError is also categorized as a server error`() {
        #expect(APIError.serverError.isServerError == true)
    }

    @Test(arguments: [APIError.cancelled, .decoding(DummyError()), .encoding(DummyError()), .invalidURL, .unknown])
    func `Local failures belong to no category`(error: APIError) {
        #expect(error.isServerError == false)
        #expect(error.isRetryable == false)
    }
}
