//
//  URLRequest+Request.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

extension URLRequest {
    /// Builds a configured request. The token travels by parameter: no interceptor,
    /// no shared mutable state. A body that fails to encode propagates as `APIError.encoding`.
    static func request(url: URL,
                        method: HTTPMethod = .get,
                        body: (any Encodable)? = nil,
                        authentication: AuthenticationType = .bearer,
                        token: String? = nil) throws(APIError) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            switch authentication {
            case .appToken:
                request.setValue(token, forHTTPHeaderField: "App-Token")
            case .basic, .bearer:
                request.setValue("\(authentication.rawValue) \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        if let body {
            do {
                request.httpBody = try JSONEncoder.app.encode(body)
            } catch {
                throw .encoding(error)
            }
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
