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
        self.thoughts = MockThoughs.getMockData()
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
