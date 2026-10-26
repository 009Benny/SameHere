//
//  MyThoughtsView.swift
//  SameHere
//
//  Created by Benny Reyes on 04/08/26.
//

import AuthFeature
import SwiftUI

struct MyThoughtsView : View {
    @StateObject private var viewModel = MyThoughtsViewModel()
    @Namespace private var animation
    @State private var showCreateSheet = false

    /// Optional so the SwiftUI preview below still works outside the auth gate.
    /// Behind the gate it is always present.
    @Environment(AppServices.self) private var services: AppServices?
    @State private var isShowingUpgrade = false
    @State private var hasDismissedGuestBanner = false
    @State private var signInGate: GuestRestrictedAction? = nil
    /// Which sections are open. Remembered between launches.
    @AppStorage("myThoughts.isIdeasExpanded") private var isIdeasExpanded = true
    @AppStorage("myThoughts.isVotesExpanded") private var isVotesExpanded = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundView()
                VStack(spacing: 0) {
                    if let services, services.isGuest, !hasDismissedGuestBanner {
                        GuestBanner(thoughtCount: viewModel.thoughts.count) {
                            isShowingUpgrade = true
                        } onDismiss: {
                            withAnimation { hasDismissedGuestBanner = true }
                        }
                        .padding(.vertical, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ScrollView {
                        VStack(spacing: 16) {
                            ThoughtsCard(
                                title: "My own ideas",
                                thoughts: viewModel.thoughts,
                                isExpanded: $isIdeasExpanded,
                                isLoading: viewModel.isLoading,
                                errorMessage: viewModel.errorMessage,
                                errorTitle: "Couldn't load your ideas",
                                emptyTitle: "No ideas yet",
                                emptyMessage: "Tap + to share your first thought.",
                                animation: animation
                            )
                            ThoughtsCard(
                                title: "My votes",
                                thoughts: viewModel.votes,
                                isExpanded: $isVotesExpanded,
                                isLoading: viewModel.isLoadingVotes,
                                errorMessage: viewModel.votesErrorMessage,
                                errorTitle: "Couldn't load your votes",
                                emptyTitle: "No votes yet",
                                emptyMessage: "Answer questions in Home and they'll show up here.",
                                animation: animation
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .refreshable {
                        await viewModel.loadData()
                        await viewModel.loadVotes()
                    }
                    
                }
                // The title is drawn inside the card. It stays set here because
                // it is the back-button label on the detail screen; the empty
                // `.principal` item keeps it from also showing in the bar.
//                .navigationTitle("My own ideas")
                .toolbarTitleDisplayMode(.inline)
                .navigationDestination(for: Thought.self, destination: { thought in
                    // A voted thought shows the user's own pick (and can't be
                    // changed: no `answerAction`); their own thoughts show
                    // every result.
                    ThoughView(
                        thought: thought,
                        isFullScreen: true,
                        isDetail: thought.myVoteOptionID == nil,
                        animation: animation
                    )
                    // The system zoom transition, not matchedGeometryEffect:
                    // it follows the interactive swipe-back gesture. A shared
                    // matchedGeometryEffect across a push left the card shrunk
                    // in the corner when that swipe was cancelled.
                    .navigationTransition(.zoom(sourceID: thought.id, in: animation))
                })
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        EmptyView()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("+", action: {
                            // Guests can read and vote, not post.
                            if services?.isGuest == true {
                                signInGate = .createThought
                            } else {
                                showCreateSheet = true
                            }
                        })
                    }
                }
                .sheet(isPresented: $showCreateSheet) {
                    CreateThoughSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $isShowingUpgrade) {
                    if let services {
                        UpgradeAccountSheet(auth: services.auth)
                    }
                }
                .guestSignInGate($signInGate)
            }
        }
        .task {
            if let services, let user = services.currentUser {
                viewModel.configure(repository: services.thoughts, currentUserID: user.id)
            }
            // Only the first time: `.task` runs again on every return to the tab.
            if viewModel.thoughts.isEmpty {
                await viewModel.loadData()
            }
            // Every time: the user may have just voted in Home.
            await viewModel.loadVotes()
        }
    }
    
}

/// A collapsible section of the tab: a title (tap it to fold the list away)
/// and a list of thoughts, on a rounded card styled like the Home cards so the
/// text stays readable over the gradient background. Sized to its rows rather
/// than stretched to the bottom of the screen like a `List` would be.
private struct ThoughtsCard: View {
    let title: LocalizedStringKey
    let thoughts: [Thought]
    @Binding var isExpanded: Bool
    var isLoading: Bool = false
    var errorMessage: String? = nil
    let errorTitle: LocalizedStringKey
    let emptyTitle: LocalizedStringKey
    let emptyMessage: LocalizedStringKey
    var animation: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Divider()
                    .padding(.leading, 16)

                if thoughts.isEmpty {
                    placeholder
                } else {
                    rows
                }
            }
        }
        // Same surface as the Home cards (`viewGlassContainer`): the
        // `glassBackground` color over thin material, so both tabs match in
        // light and dark mode and the text color adapts with them.
        .background(Color.glassBackground)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .circular))
        .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 2)
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.title.bold())
                if !thoughts.isEmpty {
                    Text(thoughts.count, format: .number)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, isExpanded ? 8 : 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                Text(errorTitle)
                    .font(.headline)
                Text(errorMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text(emptyTitle)
                    .font(.headline)
                Text(emptyMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(thoughts) { thought in
            NavigationLink(value: thought) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(thought.message)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                        if let pick = votedOptionTitle(in: thought) {
                            Text("You voted: \(pick)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
            .buttonStyle(.plain)

            if thought.id != thoughts.last?.id {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }

    private func votedOptionTitle(in thought: Thought) -> String? {
        guard let id = thought.myVoteOptionID else { return nil }
        return thought.options.first { $0.id == id }?.title
    }
}

struct CreateOptionItem: Identifiable {
    let id = UUID()
    var text: String = ""
}

struct CreateThoughSheet: View {
    @ObservedObject var viewModel: MyThoughtsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var topic: Topic = .general
    @State private var options = [CreateOptionItem(), CreateOptionItem()]
    @State private var isSaving = false
    @State private var saveError: String?

    /// Same range the seed script enforces.
    private let minOptions = 2
    private let maxOptions = 6
    
    private var isFormValid: Bool {
        let isMessageValid = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let areOptionsValid = options.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        return isMessageValid && areOptionsValid && (minOptions...maxOptions).contains(options.count)
    }
    
    var body: some View {
        NavigationStack{
            Form {
                Section(header: Text("Tell us your thought")) {
                    TextField("Thought", text: $message, axis: .vertical)
                }
                Section(header: Text("Topic")) {
                    Picker("Topic", selection: $topic) {
                        ForEach(Topic.allCases) { topic in
                            Text(topic.title).tag(topic)
                        }
                    }
                }
                Section(
                    header: Text("Options"),
                    footer: Text("Between \(minOptions) and \(maxOptions) options.")
                ) {
                    ForEach($options) { $option in
                        TextField("...", text: $option.text)
                    }
                    .onDelete(perform: deleteOption(at:))
                    
                    Button(action: {
                        withAnimation {
                            options.append(CreateOptionItem())
                        }
                    }) {
                        Label("Add option", systemImage: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(options.count >= maxOptions)
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(isSaving)
            // Keep the system grouped background: hiding it left white rows on
            // a white sheet in light mode, so the fields disappeared.
            .navigationTitle("Create a thought")
            // Don't let a swipe-down drop the sheet mid-save.
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .tint(.red)
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await saveIdea() }
                        }
                        .tint(.blue)
                        .disabled(!isFormValid)
                    }
                }
            }
        }
    }
    
    private func deleteOption(at offsets: IndexSet) {
        options.remove(atOffsets: offsets)
        if options.count < 2 {
            options.append(CreateOptionItem())
        }
    }
    
    /// Closes the sheet only once the thought is saved; on failure it stays
    /// open with the error, so nothing the user typed is lost.
    private func saveIdea() async {
        isSaving = true
        saveError = nil
        do {
            try await viewModel.createThought(
                message: message,
                topic: topic,
                options: options.map(\.text)
            )
            dismiss()
        } catch {
            saveError = String(localized: "Couldn't save your thought: \(error.localizedDescription)")
        }
        isSaving = false
    }
    
}

#Preview {
    MyThoughtsView()
}
