//
//  Data+Base64URL.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

extension Data {
    /// Decodes base64url without padding (the alphabet of JWT segments: `-` and `_` instead of
    /// `+` and `/`). Returns `nil` for characters outside the alphabet or an impossible length.
    init?(base64URLEncoded string: String) {
        guard !string.contains(where: { "+/=".contains($0) }) else {
            return nil
        }
        var base64 = string
            .replacing("-", with: "+")
            .replacing("_", with: "/")
        let remainder = base64.count % 4
        guard remainder != 1 else {
            return nil
        }
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }
}
