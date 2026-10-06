//
//  HomeView.swift
//  sameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import Foundation
import Combine

class HomeViewModel: ObservableObject {
    /// The card stack. The **last** element is the card on top.
    @Published var thoughts:[Thought] = []
    @Published var selectedThought: Thought? = nil
    /// A page request is in flight.
    @Published private(set) var isFetching = false
    @Published var errorMessage: String? = nil

    /// Cards fetched per request.
    private let pageSize = 10
    /// Fetch the next page when this many cards (or fewer) are left, so it has
    /// arrived by the time the user reaches the bottom of the stack.
    private let prefetchThreshold = 3

    /// Set by `configure(...)` once the view can see `AppServices`.
    /// `nil` in SwiftUI previews, where the feed falls back to `MockThoughs`.
    private var repository: ThoughtsRepository?
    private var currentUserID: UUID?

    private var nextCursor: FeedCursor?
    private var hasMore = true
    /// Every thought put on the stack this session. A reload never shows these
    /// again — answered ones are also excluded server-side, skipped ones only
    /// here, so they come back on the next app launch.
    private var shownIDs: Set<UUID> = []

    /// Show the spinner instead of "all caught up": the stack is empty but the
    /// next page is on its way (also when it ran out mid-prefetch).
    var isLoading: Bool { isFetching && thoughts.isEmpty }

    /// `HomeView` builds this view model before the environment is available,
    /// so the real dependencies are handed over here, from `.task`.
    func configure(repository: ThoughtsRepository, currentUserID: UUID) {
        guard self.repository == nil else { return }
        self.repository = repository
        self.currentUserID = currentUserID
    }

    /// First load, and the "Reload" button. Starts again from the newest
    /// thought, so anything posted since shows up, minus what was already shown.
    public func loadData() async {
        guard repository != nil else {
            self.thoughts = MockThoughs.getMockData()
            return
        }
        guard !isFetching else { return }
        nextCursor = nil
        hasMore = true
        await loadMore()
    }

    /// Appends the next page underneath the current cards.
    public func loadMore() async {
        guard let repository, hasMore, !isFetching else { return }
        isFetching = true
        errorMessage = nil
        defer { isFetching = false }

        do {
            // A page can come back empty when everything in it was already
            // shown or answered; keep going a little while the stack is low.
            var attempts = 0
            repeat {
                let page = try await repository.fetchFeedPage(
                    after: nextCursor,
                    pageSize: pageSize,
                    // Your own thoughts live in the My Thoughts tab, not the feed.
                    excludingAuthor: currentUserID
                )
                nextCursor = page.nextCursor
                hasMore = page.nextCursor != nil

                let fresh = page.thoughts.filter { !shownIDs.contains($0.id) }
                shownIDs.formUnion(fresh.map(\.id))
                // Pages arrive newest-first and are older than what's on screen,
                // so they go *under* the stack (the front of the array), reversed
                // so the newest of the page ends up nearest the top.
                thoughts.insert(contentsOf: fresh.reversed(), at: 0)
                attempts += 1
            } while hasMore && thoughts.count <= prefetchThreshold && attempts < 3
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func swipeItem(_ thought:Thought, direction: SwipeDirection){
        removeFromStack(thought)
    }

    public func answerItem(_ thought:Thought, option: UUID){
        // Remove the card right away so the swipe animation isn't held up by
        // the network; the vote is saved in the background.
        removeFromStack(thought)

        guard let repository, let currentUserID else { return }
        Task {
            do {
                try await repository.vote(
                    thoughtID: thought.id,
                    optionID: option,
                    userID: currentUserID
                )
            } catch SupabaseRequestError.duplicate {
                // Already voted on this one — the unique constraint doing its
                // job. Not worth an alert.
            } catch {
                errorMessage = "Your answer wasn't saved: \(error.localizedDescription)"
            }
        }
    }

    private func removeFromStack(_ thought: Thought) {
        thoughts.removeAll { $0.id == thought.id }
        if thoughts.count <= prefetchThreshold {
            Task { await loadMore() }
        }
    }

}

enum SwipeDirection {
    case left
    case right
}
