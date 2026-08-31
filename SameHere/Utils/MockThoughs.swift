//
//  MockThoughs.swift
//  SameHere
//
//  Created by Benny Reyes on 31/08/26.
//

import Foundation

struct MockThoughs {
    static func getMockData() -> [Thought] {
        return [
            Thought(
                id: UUID(),
                user: User(id: UUID(), name: "Benny", email: "mail@mail.com"),
                message: "Are you unemployed?",
                options: [
                    OptionItem(id: UUID(), title: "Yes, I am", counter: 20),
                    OptionItem(id: UUID(), title: "No, I'm not", counter: 50)
                ],
                topic: "Work"
            ),
            Thought(
                id: UUID(),
                user: User(id: UUID(), name: "Sandy", email: "mail@mail.com"),
                message: "iOS or Android?",
                options: [
                    OptionItem(id: UUID(), title: "iOS", counter: 50),
                    OptionItem(id: UUID(), title: "Android", counter: 20)
                ],
                topic: "Work"
            ),
            Thought(
                id: UUID(),
                user: User(id: UUID(), name: "Benny", email: "mail@mail.com"),
                message: "Do you belive in GOD?",
                options: [
                    OptionItem(id: UUID(), title: "Yes, I am", counter: 100),
                    OptionItem(id: UUID(), title: "No, I'm not", counter: 666)
                ],
                topic: "Work"
            ),
            Thought(
                id: UUID(),
                user: User(id: UUID(), name: "Sandy", email: "mail@mail.com"),
                message: "Cats or dogs?",
                options: [
                    OptionItem(id: UUID(), title: "Cats 🐱", counter: 20),
                    OptionItem(id: UUID(), title: "Dogs 🐶", counter: 50),
                    OptionItem(id: UUID(), title: "Reptiles 🐢", counter: 50),
                    OptionItem(id: UUID(), title: "Reptiles 🐢", counter: 50)
                ],
                topic: "Work"
            ),
            Thought(
                id: UUID(),
                user: User(id: UUID(), name: "Benny", email: "mail@mail.com"),
                message: "Rock or Pop?",
                options: [
                    OptionItem(id: UUID(), title: "Rockkkk 🤘", counter: 20),
                    OptionItem(id: UUID(), title: "Pop 🍬", counter: 50)
                ],
                topic: "Work"
            ),
            
        ]
    }
}
