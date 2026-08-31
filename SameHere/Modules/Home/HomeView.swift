//
//  Home.swift
//  sameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import SwiftUI

struct HomeView: View {
    @StateObject var viewModel = HomeViewModel()
    @State private var selectedTought: Thought? = nil
    @Namespace private var animation
    
    var body: some View {
        NavigationStack {
            ZStack {
                
                BackgroundView()
                
                ForEach(viewModel.thoughts) { thought in
                    SwipeCardView(
                        content: ItemView(thought: thought),
                        swipeAction: { direction in
                            viewModel.swipeItem(thought, direction: direction)
                        },
                        onTapAction: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                self.selectedTought = thought
                            }
                        })
//                        .opacity(selectedTought == nil ? 1 : 0)
                        .allowsHitTesting(thought.id == viewModel.thoughts.last?.id)
                }
                
                if let selected = selectedTought {
                    ItemView(thought: selected, isFullScreen: true)
                }
                
            }
        }
        .safeAreaPadding(10)
        .task {
            await viewModel.loadData()
        }
    }
    
    @ViewBuilder
    func ItemView(
        thought: Thought,
        isFullScreen: Bool = false,
    ) -> some View {
        ThoughView(
            thought: thought,
            isFullScreen: isFullScreen,
            isDetail: false,
            animation: animation,
            answerAction: { optionSelected in
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    viewModel.answerItem(thought, option: optionSelected)
                }
            },
            closeAction: {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                    selectedTought = nil
                }
            }
        )
    }
    
}

#Preview {
    HomeView()
}
