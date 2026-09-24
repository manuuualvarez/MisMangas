//
//  UsersCreate.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

/// Body of `POST /users`: the credentials of the account to create (OpenAPI).
struct UsersCreate: Codable {
    let email: String
    let password: String
}
