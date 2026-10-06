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
                        ThoughtsCard(
                            title: "My own ideas",
                            thoughts: viewModel.thoughts,
                            isLoading: viewModel.isLoading,
                            errorMessage: viewModel.errorMessage,
                            animation: animation
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    
                }
                // The title is drawn inside the card. It stays set here because
                // it is the back-button label on the detail screen; the empty
                // `.principal` item keeps it from also showing in the bar.
//                .navigationTitle("My own ideas")
                .toolbarTitleDisplayMode(.inline)
                .navigationDestination(for: Thought.self, destination: { thought in
                    ThoughView(
                        thought: thought,
                        isFullScreen: true,
                        isDetail: true,
                        animation: animation
                    )
                })
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        EmptyView()
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        AccountMenu(isShowingUpgrade: $isShowingUpgrade)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("+", action: {
                            showCreateSheet = true
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
        }
    }
    
}

/// The title and the list of the user's thoughts, on a rounded card styled like
/// the Home cards so the text stays readable over the gradient background. Sized to its rows rather
/// than stretched to the bottom of the screen like a `List` would be.
private struct ThoughtsCard: View {
    let title: String
    let thoughts: [Thought]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var animation: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

            Divider()
                .padding(.leading, 16)

            if thoughts.isEmpty {
                VStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                    } else if let errorMessage {
                        Text("Couldn't load your ideas")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No ideas yet")
                            .font(.headline)
                        Text("Tap + to share your first thought.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
            } else {
                rows
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

    @ViewBuilder
    private var rows: some View {
        ForEach(thoughts) { thought in
            NavigationLink(value: thought) {
                HStack(spacing: 12) {
                    Text(thought.message)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .matchedGeometryEffect(id: "background_\(thought.id)", in: animation)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if thought.id != thoughts.last?.id {
                Divider()
                    .padding(.leading, 16)
            }
        }
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
            saveError = "Couldn't save your thought: \(error.localizedDescription)"
        }
        isSaving = false
    }
    
}

#Preview {
    MyThoughtsView()
}
