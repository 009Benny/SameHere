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
    /// The top card plus the one revealed while it is swiped away.
    private let visibleCardCount = 2

    /// Optional so the preview below still works outside the auth gate, on mocks.
    /// Behind the gate it is always present.
    @Environment(AppServices.self) private var services: AppServices?
    
    var body: some View {
        NavigationStack {
            ZStack {
                
                BackgroundView()
                
                // Only the top two cards are drawn, and only the top one casts a
                // shadow. The card material is translucent (very much so in dark
                // mode), so shadows of the cards underneath show through it and
                // stack up into a dark frame.
                ForEach(viewModel.thoughts.suffix(visibleCardCount)) { thought in
                    SwipeCardView(
                        content: StackCard(
                            thought: thought,
                            castsShadow: thought.id == viewModel.thoughts.last?.id
                        ),
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
                        // A fresh view (and fresh vote state) per thought. Without
                        // this, opening another thought while the previous one was
                        // still animating closed reused the old view — keeping its
                        // chosen option, which locked every option of the new one.
                        .id(selected.id)
                        .zIndex(1)
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
    
    /// A card in the stack. While that thought is open full screen, its slot
    /// is left empty: both views use the same `matchedGeometryEffect` id, and
    /// with two of them on screen SwiftUI mixes their frames and the card
    /// comes out stretched. One at a time, the card animates open and closed.
    @ViewBuilder
    func StackCard(thought: Thought, castsShadow: Bool) -> some View {
        if selectedTought?.id == thought.id {
            Color.clear
                .frame(height: 300)
                .padding(20)
        } else {
            ItemView(thought: thought, castsShadow: castsShadow)
        }
    }

    @ViewBuilder
    func ItemView(
        thought: Thought,
        isFullScreen: Bool = false,
        castsShadow: Bool = true
    ) -> some View {
        ThoughView(
            thought: thought,
            isFullScreen: isFullScreen,
            isDetail: false,
            animation: animation,
            answerAction: { optionSelected in
                // Vote first; only once it is saved does the card leave the
                // stack and the detail show the new percentages.
                let results = try await viewModel.answer(thought, option: optionSelected)
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    viewModel.removeFromStack(thought)
                }
                return results
            },
            closeAction: {
                // Same spring as opening, so the card settles back in place
                // instead of bouncing past it.
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    selectedTought = nil
                }
            },
            castsShadow: castsShadow,
            reportAction: { reason in
                try await viewModel.report(thought, reason: reason)
            },
            // Only offered for thoughts with an author; ThoughView checks.
            blockAction: {
                try await viewModel.blockAuthor(of: thought)
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
                Group {
                    if errorMessage == nil {
                        Text("You're all caught up")
                    } else {
                        Text("Couldn't load thoughts")
                    }
                }
                .font(.headline)
                Group {
                    if let errorMessage {
                        Text(errorMessage)
                    } else {
                        Text("Check back later for new thoughts.")
                    }
                }
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
