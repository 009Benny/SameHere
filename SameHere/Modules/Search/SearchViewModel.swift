//
//  SearchViewModel.swift
//  SameHere
//

import Foundation
import Combine

class SearchViewModel: ObservableObject {
    /// Results for `searchedText`, newest first.
    @Published private(set) var results: [Thought] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String? = nil
    /// The text `results` belong to. `nil` until a search has finished.
    @Published private(set) var searchedText: String? = nil

    /// Shorter queries match almost everything, so they aren't sent.
    static let minimumLength = 2

    /// Set by `configure(...)` once the view can see `AppServices`.
    /// `nil` in SwiftUI previews, where results come from `MockThoughs`.
    private var repository: ThoughtsRepository?
    private var currentUserID: UUID?

    func configure(repository: ThoughtsRepository, currentUserID: UUID) {
        guard self.repository == nil else { return }
        self.repository = repository
        self.currentUserID = currentUserID
    }

    /// Runs a search. The view calls it from a `.task(id:)` keyed on the
    /// text, so a new keystroke cancels the previous search; a cancelled one
    /// leaves no trace.
    func search(_ text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= Self.minimumLength else {
            results = []
            searchedText = nil
            errorMessage = nil
            isSearching = false
            return
        }
        guard let repository else {
            results = MockThoughs.getMockData().filter { $0.message.localizedCaseInsensitiveContains(text) }
            searchedText = text
            return
        }

        isSearching = true
        errorMessage = nil
        do {
            let found = try await repository.searchThoughts(matching: text)
            guard !Task.isCancelled else { return }
            results = found
            searchedText = text
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            results = []
            searchedText = text
        }
        isSearching = false
    }

    /// The signed-in user wrote it: shown with every result, never voted on.
    func isOwn(_ thought: Thought) -> Bool {
        currentUserID != nil && thought.authorID == currentUserID
    }

    /// Saves the vote and returns fresh counts, like Home does. The result in
    /// the list is updated too, so reopening it shows the vote.
    func answer(_ thought: Thought, option: UUID) async throws -> [OptionItem] {
        let fresh: [OptionItem]
        if let repository, let currentUserID {
            do {
                try await repository.vote(thoughtID: thought.id, optionID: option, userID: currentUserID)
            } catch SupabaseRequestError.duplicate {
                // Already voted (e.g. from Home) — the counts below include it.
            }
            fresh = try await repository.fetchOptionResults(thoughtID: thought.id)
        } else {
            // Preview: no backend, so just count the vote locally.
            fresh = thought.options.map {
                $0.id == option ? OptionItem(id: $0.id, title: $0.title, counter: $0.counter + 1) : $0
            }
        }

        if let index = results.firstIndex(where: { $0.id == thought.id }) {
            var voted = Thought(
                id: thought.id,
                user: thought.user,
                message: thought.message,
                options: fresh,
                topic: thought.topic,
                sourceURL: thought.sourceURL,
                authorID: thought.authorID
            )
            voted.myVoteOptionID = option
            results[index] = voted
        }
        return fresh
    }

    /// Reports the thought and drops it from the results.
    func report(_ thought: Thought, reason: ReportReason) async throws {
        if let repository, let currentUserID {
            try await repository.report(thoughtID: thought.id, reason: reason, reporterID: currentUserID)
        }
        results.removeAll { $0.id == thought.id }
    }

    /// Blocks the author and drops everything of theirs from the results.
    func blockAuthor(of thought: Thought) async throws {
        guard let authorID = thought.authorID else { return }
        if let repository, let currentUserID {
            try await repository.block(userID: authorID, blockerID: currentUserID)
        }
        results.removeAll { $0.authorID == authorID }
    }
}
