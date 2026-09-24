//
//  JWTTokenDTO.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

/// Response of `POST /users/jwt/login` and `POST /users/jwt/refresh`: a JWT valid for
/// `expiresIn` seconds (86400, 24 h).
struct JWTTokenDTO: Codable {
    let token: String
    let expiresIn: Int
    let tokenType: String
}
