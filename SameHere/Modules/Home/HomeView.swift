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
    private let visibleCardCount = 3

    /// Optional so the preview below still works outside the auth gate, on mocks.
    /// Behind the gate it is always present.
    @Environment(AppServices.self) private var services: AppServices?
    
    var body: some View {
        NavigationStack {
            ZStack {
                
                BackgroundView()
                
                // Only the top few cards are drawn. The rest are hidden behind
                // them anyway, but each one adds its shadow, and a deep stack
                // turns those shadows into a dark frame around the card.
                ForEach(viewModel.thoughts.suffix(visibleCardCount)) { thought in
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
                
                if viewModel.thoughts.isEmpty {
                    FeedStatusView(
                        isLoading: viewModel.isLoading,
                        errorMessage: viewModel.errorMessage,
                        reload: { await viewModel.loadData() }
                    )
                } else if let errorMessage = viewModel.errorMessage {
                    VStack {
                        Spacer()
                        Text(errorMessage)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { viewModel.errorMessage = nil }
                    }
                }

                if let selected = selectedTought {
                    ItemView(thought: selected, isFullScreen: true)
                }
                
            }
        }
        .safeAreaPadding(10)
        .task {
            if let services, let user = services.currentUser {
                viewModel.configure(repository: services.thoughts, currentUserID: user.id)
            }
            // `.task` runs again every time the Home tab reappears; only fetch
            // when the stack is empty so switching tabs doesn't reshuffle it.
            if viewModel.thoughts.isEmpty {
                await viewModel.loadData()
            }
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

/// What the feed shows when there are no cards: loading, an error, or "all done".
private struct FeedStatusView: View {
    let isLoading: Bool
    let errorMessage: String?
    let reload: () async -> Void

    var body: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: errorMessage == nil ? "checkmark.circle" : "wifi.exclamationmark")
                    .font(.system(size: 40))
                Text(errorMessage == nil ? "You're all caught up" : "Couldn't load thoughts")
                    .font(.headline)
                Text(errorMessage ?? "Check back later for new thoughts.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Reload") {
                    Task { await reload() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
    }
}

#Preview {
    HomeView()
}
