//
//  ThoughView.swift
//  SameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import SwiftUI

struct ThoughView: View {
    let thought: Thought
    let isFullScreen:Bool
    var isDetail:Bool
    var animation: Namespace.ID
    /// Saves the vote for the given option and returns the options with fresh
    /// counts (including that vote). Throws if the vote wasn't saved.
    var answerAction: ((UUID) async throws -> [OptionItem])?
    var closeAction: (() -> ())?
    /// Off for cards stacked under the top one (see `viewGlassContainer`).
    var castsShadow: Bool = true
    /// Reports the thought. When set, the open card shows a "⋯" menu.
    var reportAction: ((ReportReason) async throws -> Void)? = nil
    /// Blocks the thought's author. Only offered for thoughts that have one.
    var blockAction: (() async throws -> Void)? = nil
    @State private var isChoosingReportReason = false
    @State private var isConfirmingBlock = false
    @State private var moderationError: String? = nil
    @State private var selected: UUID? = nil
    /// The option whose vote is being saved right now.
    @State private var pending: UUID? = nil
    /// Counts returned after voting. Until then, the ones the card came with.
    @State private var results: [OptionItem]? = nil
    @State private var voteError: String? = nil
    
    var body: some View {
        let options = results ?? thought.options
        let total = options.reduce(0) { $0 + $1.counter }
        ZStack{
            if isFullScreen {
                BackgroundView()
            }
            VStack {
                if isFullScreen && closeAction != nil {
                    HStack {
                        if reportAction != nil {
                            moderationMenu
                        }
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                closeAction?()
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
        
                    Spacer()
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .circular)
                        // hPadding 0: the shape *is* the card. With the default
                        // padding it is drawn 10 pt narrower than the material
                        // behind it, which shows as a dark band on both sides
                        // in dark mode.
                        .viewGlassContainer(height: 300, hPadding: 0, castsShadow: castsShadow)
                        .matchedGeometryEffect(id: "background_\(thought.id)", in: animation)
                    
                    Text(thought.message)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .font(.headline)
                        .padding(10)
                }
                .overlay(alignment: .bottomTrailing) {
                    originBadge
                        .padding(14)
                }
                
                
                if isFullScreen {
                    Spacer()
                    ForEach(options) { option in
                        OptionRowView(
                            option: option,
                            total: total,
                            selected: selected,
                            showPercentages: isDetail,
                            isPending: pending == option.id
                        ) {
                            Task { await vote(for: option.id) }
                        }
                    }
                    if let message = voteError ?? moderationError {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
            }
            .padding(20)
        }
    }

    /// Report / block, top-left of the open card.
    private var moderationMenu: some View {
        Menu {
            Button {
                isChoosingReportReason = true
            } label: {
                Label("Report thought", systemImage: "flag")
            }
            if blockAction != nil, thought.authorID != nil {
                Button(role: .destructive) {
                    isConfirmingBlock = true
                } label: {
                    Label("Block this person", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title)
                .foregroundColor(.white.opacity(0.7))
        }
        .accessibilityLabel("More options")
        .confirmationDialog(
            "Why are you reporting this thought?",
            isPresented: $isChoosingReportReason,
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.title) {
                    Task { await moderate { try await reportAction?(reason) } }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You won't see it again. Thoughts reported by several people are hidden for everyone.")
        }
        .confirmationDialog(
            "Block this person?",
            isPresented: $isConfirmingBlock,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task { await moderate { try await blockAction?() } }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You won't see their thoughts anymore.")
        }
    }

    /// Runs a report or block; on success the card closes, on failure it
    /// stays open with the error so the user can try again.
    private func moderate(_ action: () async throws -> Void) async {
        moderationError = nil
        do {
            try await action()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                closeAction?()
            }
        } catch {
            moderationError = String(localized: "That didn't go through: \(error.localizedDescription)")
        }
    }

    /// Bottom-right corner of the card: where the question comes from.
    /// Seeded questions have a source (a clip, or a "View source" link once the
    /// card is open); questions written in the app show a person.
    @ViewBuilder
    private var originBadge: some View {
        if let url = thought.sourceURL {
            if isFullScreen {
                Link(destination: url) {
                    Label("View source", systemImage: "paperclip")
                        .font(.footnote.weight(.semibold))
                        .underline()
                }
            } else {
                Image(systemName: "paperclip")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Has a source")
            }
        } else {
            Image(systemName: "person.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Written by a community member")
        }
    }

    /// Saves the vote first and only then reveals the percentages, computed
    /// from the server's counts so they include this vote.
    private func vote(for optionID: UUID) async {
        guard let answerAction, selected == nil, pending == nil else { return }
        pending = optionID
        voteError = nil
        do {
            let fresh = try await answerAction(optionID)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                results = fresh
                selected = optionID
            }
        } catch {
            voteError = String(localized: "Your answer wasn't saved: \(error.localizedDescription)")
        }
        pending = nil
    }
}

#Preview {
    HomeView()
}
