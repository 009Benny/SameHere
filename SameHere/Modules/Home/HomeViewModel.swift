//
//  HomeView.swift
//  sameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import Foundation
import Combine

class HomeViewModel: ObservableObject {
    @Published var thoughts:[Thought] = []
    @Published var selectedThought: Thought? = nil
    
    public func loadData() async {
        self.thoughts = getData()
    }
    
    public func swipeItem(_ thought:Thought, direction: SwipeDirection){
        thoughts.removeAll { $0.id == thought.id }
    }
    
    public func answerItem(_ thought:Thought, option: UUID){
        print("answering thought: \(thought.message)")
        thoughts.removeAll { $0.id == thought.id }
    }
    
}

enum SwipeDirection {
    case left
    case right
}

extension HomeViewModel {
    func getData()-> [Thought]{
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
