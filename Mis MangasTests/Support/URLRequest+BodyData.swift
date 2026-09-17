//
//  URLRequest+BodyData.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

extension URLRequest {
    /// The request body as seen from inside a `URLProtocol`. `URLSession` hands the body to
    /// custom protocols as `httpBodyStream` (never as `httpBody`, verified empirically), so the
    /// stream is drained here; a plain `httpBody` is returned as-is when present.
    var bodyData: Data? {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            return nil
        }
        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while httpBodyStream.hasBytesAvailable {
            let bytesRead = httpBodyStream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}
