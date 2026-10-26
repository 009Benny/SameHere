//
//  SearchView.swift
//  SameHere
//

import SwiftUI

/// The Search tab: find thoughts by their text. Unanswered ones can be voted
/// on from here; answered ones show the user's vote; their own show results.
struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @Namespace private var animation
    @State private var text = ""
    @State private var path: [Thought] = []

    /// Optional so the SwiftUI preview below still works outside the auth gate.
    @Environment(AppServices.self) private var services: AppServices?

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                BackgroundView()
                content
            }
            .navigationTitle("Search")
            .searchable(text: $text, prompt: "Search thoughts")
            .navigationDestination(for: Thought.self) { thought in
                detail(for: thought)
            }
        }
        .task {
            if let services, let user = services.currentUser {
                viewModel.configure(repository: services.thoughts, currentUserID: user.id)
            }
        }
        .task(id: text) {
            // Wait for a pause in typing; each keystroke cancels this task.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.search(text)
        }
    }

    @ViewBuilder
    private var content: some View {
        if trimmedText.count < SearchViewModel.minimumLength {
            ContentUnavailableView(
                "Search thoughts",
                systemImage: "magnifyingglass",
                description: Text("Find questions by what they say.")
            )
        } else if !viewModel.results.isEmpty {
            ScrollView {
                resultsCard
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.immediately)
        } else if viewModel.isSearching || viewModel.searchedText != trimmedText {
            ProgressView()
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "Couldn't search",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else {
            ContentUnavailableView.search(text: trimmedText)
        }
    }

    /// Same rounded surface as the My Thoughts cards.
    private var resultsCard: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.results) { thought in
                NavigationLink(value: thought) {
                    row(for: thought)
                }
                .buttonStyle(.plain)

                if thought.id != viewModel.results.last?.id {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
        .background(Color.glassBackground)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .circular))
        .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 2)
    }

    private func row(for thought: Thought) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(thought.message)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let topic = Topic(rawValue: thought.topic) {
                        Text(topic.title)
                        Text("·")
                    }
                    Text("\(thought.getTotal()) votes")
                    if thought.myVoteOptionID != nil {
                        Label("Voted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    } else if viewModel.isOwn(thought) {
                        Label("Yours", systemImage: "person.fill")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        // Where the detail zooms out from, and back into.
        .matchedTransitionSource(id: thought.id, in: animation)
    }

    private func detail(for thought: Thought) -> some View {
        let isOwn = viewModel.isOwn(thought)
        let canVote = !isOwn && thought.myVoteOptionID == nil

        let answer: ((UUID) async throws -> [OptionItem])? = canVote ? { option in
            try await viewModel.answer(thought, option: option)
        } : nil
        let report: ((ReportReason) async throws -> Void)? = isOwn ? nil : { reason in
            try await viewModel.report(thought, reason: reason)
            close(thought)
        }
        // Only offered for thoughts with an author; ThoughView checks.
        let block: (() async throws -> Void)? = isOwn ? nil : {
            try await viewModel.blockAuthor(of: thought)
            close(thought)
        }

        return ThoughView(
            thought: thought,
            isFullScreen: true,
            isDetail: isOwn,
            animation: animation,
            answerAction: answer,
            reportAction: report,
            blockAction: block
        )
        .navigationTransition(.zoom(sourceID: thought.id, in: animation))
    }

    /// Back to the results after a report or block.
    private func close(_ thought: Thought) {
        path.removeAll { $0.id == thought.id }
    }
}

#Preview {
    SearchView()
}
