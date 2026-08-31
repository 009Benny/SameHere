//
//  Thought.swift
//  sameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import Foundation

struct Thought: Identifiable, Hashable {
    let id: UUID
    let user: User
    let message: String
    let options: [OptionItem]
    let topic:String
}

struct OptionItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let counter: Int
}
