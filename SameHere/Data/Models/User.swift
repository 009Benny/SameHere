//
//  User.swift
//  sameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import Foundation

/// A person, as the UI needs them. Maps to `public.profiles`.
///
/// `email` is optional and `isGuest` exists because a guest is a real user with
/// a real id and no email — the app has to be able to say "this account is not
/// saved anywhere yet" without inventing a placeholder address.
struct User: Identifiable, Hashable {
    let id: UUID
    let name: String
    let email: String?
    let isGuest: Bool

    init(id: UUID, name: String, email: String? = nil, isGuest: Bool = false) {
        self.id = id
        self.name = name
        self.email = email
        self.isGuest = isGuest
    }

    /// Author shown for the AI-seeded thoughts, which have `author_id = NULL`.
    /// There is deliberately no fake "system" row in the database, so the stand-in
    /// lives here in the UI layer where it belongs.
    static func seeded(id: UUID) -> User {
        User(id: id, name: "Same Here", email: nil, isGuest: false)
    }
}
