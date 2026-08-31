//
//  MyThoughtsViewModel.swift
//  SameHere
//
//  Created by Benny Reyes on 04/08/26.
//

import Combine

class MyThoughtsViewModel: ObservableObject {
    @Published var thoughts: [Thought] = []
    
    func loadData() async {
        self.thoughts = MockThoughs.getMockData()
    }
}
