//
//  MyThoughtsViewModel.swift
//  SameHere
//
//  Created by Benny Reyes on 04/08/26.
//

import Foundation
import Combine

class MyThoughtsViewModel: ObservableObject {
    @Published var thoughts: [Thought] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String? = nil

    /// Set by `configure(...)` once the view can see `AppServices`.
    /// `nil` in SwiftUI previews, where the list falls back to `MockThoughs`.
    private var repository: ThoughtsRepository?
    private var currentUserID: UUID?

    /// The view builds this view model before the environment is available,
    /// so the real dependencies are handed over here, from `.task`.
    func configure(repository: ThoughtsRepository, currentUserID: UUID) {
        guard self.repository == nil else { return }
        self.repository = repository
        self.currentUserID = currentUserID
    }

    /// The signed-in user's own thoughts, newest first.
    func loadData() async {
        guard let repository, let currentUserID else {
            self.thoughts = MockThoughs.getMockData()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            thoughts = try await repository.fetchMyThoughts(userID: currentUserID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves a new thought, then reloads the list so it shows up with its
    /// real ids. Throws so the sheet can stay open and show what went wrong.
    func createThought(message: String, topic: Topic, options: [String]) async throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let repository, let currentUserID else {
            // Preview only: no backend, so just show it locally.
            let preview = Thought(
                id: UUID(),
                user: User(id: UUID(), name: "Preview"),
                message: message,
                options: options.map { OptionItem(id: UUID(), title: $0, counter: 0) },
                topic: topic.rawValue
            )
            thoughts.insert(preview, at: 0)
            return
        }

        try await repository.createThought(
            message: message,
            topic: topic.rawValue,
            options: options,
            authorID: currentUserID
        )
        await loadData()
    }
}
