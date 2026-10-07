//
//  ProfileView.swift
//  SameHere
//

import AuthFeature
import SwiftUI

/// The Profile tab: who is signed in, and the account actions — save a guest
/// account, sign out, and delete the account.
///
/// Sign-out is guarded rather than immediate. For a saved account it is a normal
/// destructive action; for a **guest** it destroys the account outright — there
/// are no credentials to come back with — so it asks first, and offers the
/// alternative in the same breath. Deleting the account always asks first.
struct ProfileView: View {
    @Environment(AppServices.self) private var services: AppServices?
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator?

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
            .sheet(isPresented: $isShowingUpgrade) {
                if let services {
                    UpgradeAccountSheet(auth: services.auth)
                }
            }
            .confirmationDialog(
                "Sign out and delete this guest account?",
                isPresented: $isConfirmingGuestSignOut,
                titleVisibility: .visible
            ) {
                Button("Save my account instead") { isShowingUpgrade = true }
                Button("Sign out and lose everything", role: .destructive) {
                    Task { await coordinator?.signOut() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A guest account has no email or password, so there's no way back into it. Your thoughts and answers would be gone for good.")
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
