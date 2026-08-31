//
//  User.swift
//  sameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import Foundation

struct User: Identifiable, Hashable {
    let id: UUID
    let name: String
    let email: String
}
