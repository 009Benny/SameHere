//
//  MyThoughtsView.swift
//  SameHere
//
//  Created by Benny Reyes on 04/08/26.
//

import SwiftUI

struct MyThoughtsView : View {
    @StateObject private var viewModel = MyThoughtsViewModel()
    @Namespace private var animation
    
    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundView()
                VStack{
                    List{
                        ForEach(viewModel.thoughts) { thought in
                            NavigationLink(value: thought) {
                                Text(thought.message)
                                    .matchedGeometryEffect(id: "background_\(thought.id)", in: animation)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    
                }
                .navigationTitle("My own ideas")
                .navigationDestination(for: Thought.self, destination: { thought in
                    ThoughView(
                        thought: thought,
                        isFullScreen: true,
                        isDetail: true,
                        animation: animation
                    )
                })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("+", action: {
                            
                        })
                    }
                }
            }
        }
        .task {
            await viewModel.loadData()
        }
    }
    
}


#Preview {
    MyThoughtsView()
}
