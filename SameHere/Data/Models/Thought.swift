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
    
    func getTotal() -> Int{
        options.reduce(0, {$0 + $1.counter})
    }
}

struct OptionItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let counter: Int
}
