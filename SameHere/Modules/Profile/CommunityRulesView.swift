//
//  CommunityRulesView.swift
//  SameHere
//

import SwiftUI

/// The community rules every account agrees to once, before using the app.
///
/// App Review requires apps with user-generated content to have people accept
/// terms that make clear there is no tolerance for objectionable content.
/// Acceptance is stored per account (`profiles.terms_accepted_at`), so it
/// follows the person to another phone.
struct CommunityRulesView: View {
    let accept: () async throws -> Void

    @State private var isAccepting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            BackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Community rules")
                        .font(.largeTitle.bold())

                    Text("Same Here is a place to share what you think and find out who thinks the same. To keep it that way:")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        rule("hand.raised", "No hate, harassment or bullying.")
                        rule("eye.slash", "No sexual or violent content.")
                        rule("megaphone", "No spam or ads.")
                        rule("person.badge.shield.checkmark", "Respect other people's privacy.")
                    }

                    Text("There's zero tolerance for objectionable content or abusive users. You can report any thought and block anyone. Content that breaks these rules is removed, and accounts that post it may be banned.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Link("Terms of Use", destination: AppLinks.termsOfUse)
                        Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                    }
                    .font(.footnote.weight(.semibold))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await agree() }
                    } label: {
                        Group {
                            if isAccepting {
                                ProgressView()
                            } else {
                                Text("I agree")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAccepting)
                }
                .padding(24)
                .background(Color.glassBackground)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .circular))
                .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 2)
                .padding(16)
            }
        }
        .interactiveDismissDisabled()
    }

    private func rule(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: symbol)
    }

    private func agree() async {
        isAccepting = true
        errorMessage = nil
        do {
            try await accept()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAccepting = false
    }
}

#Preview {
    CommunityRulesView { }
}
