//
//  ProfileView.swift
//  SameHere
//

import AuthFeature
import SwiftUI
import UIKit

/// The Profile tab: who is signed in, and the account actions — save a guest
/// account, sign out, and delete the account.
///
/// Sign-out is guarded rather than immediate. For a saved account it is a normal
/// destructive action; for a **guest** there are no credentials to come back
/// with, so it asks first and offers to save the account instead. Signing a
/// guest out does NOT delete their data: their thoughts and votes stay on the
/// server, and the votes keep counting (anonymously) in the results. Deleting
/// the account is the separate, explicit way to erase everything; it always
/// asks first.
struct ProfileView: View {
    @Environment(AppServices.self) private var services: AppServices?
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    private var push: PushNotifications { .shared }

    @State private var isShowingUpgrade = false
    @State private var isConfirmingGuestSignOut = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private var isGuest: Bool { services?.isGuest == true }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        userCard
                        notificationsCard
                        linksCard
                        actionsCard

                        if let deleteError {
                            Text(deleteError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(16)
                }
                .disabled(isDeleting)
            }
            .navigationTitle("Profile")
            // The permission may have changed in Settings.
            .task { await push.refreshAuthorizationStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await push.refreshAuthorizationStatus() }
                }
            }
            .sheet(isPresented: $isShowingUpgrade) {
                if let services {
                    UpgradeAccountSheet(auth: services.auth)
                }
            }
            .confirmationDialog(
                "Sign out of this guest account?",
                isPresented: $isConfirmingGuestSignOut,
                titleVisibility: .visible
            ) {
                Button("Save my account instead") { isShowingUpgrade = true }
                Button("Sign out anyway", role: .destructive) {
                    // Only signs out. The guest's thoughts and votes stay on the
                    // server (votes count anonymously in the results); use
                    // "Delete account" to erase them.
                    Task { await coordinator?.signOut() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A guest account has no email or password, so you won't be able to get back into it. Your thoughts and answers stay in Same Here, but you won't be able to see or delete them.")
            }
            .confirmationDialog(
                "Sign out?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task { await coordinator?.signOut() }
                }
                Button("Sign out and forget Face ID", role: .destructive) {
                    Task { await coordinator?.signOut(forgettingCredentials: true) }
                }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes your account, your thoughts and your answers. This can't be undone.")
            }
        }
    }

    // MARK: - Cards

    /// Avatar, name and email — or, for a guest, why saving the account matters.
    private var userCard: some View {
        VStack(spacing: 10) {
            Image(systemName: isGuest
                  ? "person.crop.circle.badge.exclamationmark"
                  : "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if let user = services?.currentUser {
                Text(user.name)
                    .font(.title2.bold())
                if let email = user.email {
                    Text(email)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Guest account")
                        .foregroundStyle(.secondary)
                }
            }

            if isGuest {
                Text("You're signed in as a guest, so everything lives only on this iPhone. Add an email and you'll keep it if you switch phones.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Button("Save my account") { isShowingUpgrade = true }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .profileCard()
    }

    /// The "new questions" digest. Off until the user picks a frequency; the
    /// first time, iOS asks for permission.
    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("New questions", systemImage: "bell.badge")
                Spacer()
                Picker("New questions", selection: Binding(
                    get: { push.frequency },
                    set: { newValue in Task { await push.setFrequency(newValue) } }
                )) {
                    ForEach(DigestFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)

            if push.isDeniedInSettings {
                Text("Notifications for Same Here are turned off in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 14)
            } else {
                Text("We'll let you know when there are new questions to vote on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .profileCard()
    }

    /// Rules, privacy and a way to reach you — App Review wants a published
    /// contact for apps with user-generated content.
    private var linksCard: some View {
        VStack(spacing: 0) {
            Link(destination: AppLinks.termsOfUse) {
                actionRow("Terms of Use", systemImage: "doc.text")
            }
            Divider()
                .padding(.leading, 16)
            Link(destination: AppLinks.privacyPolicy) {
                actionRow("Privacy Policy", systemImage: "lock.shield")
            }
            Divider()
                .padding(.leading, 16)
            Link(destination: AppLinks.support) {
                actionRow("Contact support", systemImage: "envelope")
            }
        }
        .buttonStyle(.plain)
        .profileCard()
    }

    /// Sign out and delete, as rows on one card.
    private var actionsCard: some View {
        VStack(spacing: 0) {
            Button {
                if isGuest {
                    isConfirmingGuestSignOut = true
                } else {
                    isConfirmingSignOut = true
                }
            } label: {
                actionRow("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }

            Divider()
                .padding(.leading, 16)

            Button {
                isConfirmingDelete = true
            } label: {
                HStack {
                    actionRow("Delete account", systemImage: "trash")
                    if isDeleting {
                        ProgressView()
                            .padding(.trailing, 16)
                    }
                }
                .foregroundStyle(.red)
            }
        }
        .buttonStyle(.plain)
        .profileCard()
    }

    private func actionRow(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .contentShape(Rectangle())
    }

    // MARK: - Actions

    /// On success the auth gate takes over and leaves this screen; on failure
    /// the user stays signed in and sees why, so they can try again.
    private func deleteAccount() async {
        isDeleting = true
        deleteError = nil
        do {
            try await coordinator?.deleteAccount()
        } catch {
            deleteError = String(localized: "Couldn't delete your account: \(error.localizedDescription)")
        }
        isDeleting = false
    }
}

private extension View {
    /// Same surface as the Home and My Thoughts cards.
    func profileCard() -> some View {
        self
            .background(Color.glassBackground)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .circular))
            .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 2)
    }
}

#Preview {
    ProfileView()
}
