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
    /// The source a seeded question links to. `nil` means a community member
    /// wrote it in the app — the UI shows a person icon instead of a clip.
    var sourceURL: URL? = nil
    
    func getTotal() -> Int{
        options.reduce(0, {$0 + $1.counter})
    }
}

struct OptionItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let counter: Int
}
