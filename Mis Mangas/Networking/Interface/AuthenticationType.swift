//
//  AuthenticationType.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// Header-level authentication applied by `URLRequest.request(...)` when a token is given.
/// `basic` and `bearer` populate `Authorization`; `appToken` populates the proprietary
/// `App-Token` header of `POST /users`.
enum AuthenticationType: String {
    case basic = "Basic"
    case bearer = "Bearer"
    case appToken
}
