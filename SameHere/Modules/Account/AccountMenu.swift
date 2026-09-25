//
//  AccountMenu.swift
//  SameHere
//

import AuthFeature
import SwiftUI

/// Toolbar menu showing who is signed in, with the two account actions.
///
/// Sign-out is guarded rather than immediate. For a saved account it is a normal
/// destructive action; for a **guest** it destroys the account outright — there
/// are no credentials to come back with — so it asks first, and offers the
/// alternative in the same breath.
struct AccountMenu: View {
    @Environment(AppServices.self) private var services: AppServices?
    @Environment(AppCoordinator.self) private var coordinator: AppCoordinator?

    /// Owned by the screen, so the guest banner and this menu open the same sheet.
    @Binding var isShowingUpgrade: Bool

    @State private var isConfirmingGuestSignOut = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        Menu {
            if let user = services?.currentUser {
                Section {
                    Text(user.name)
                    if let email = user.email {
                        Text(email)
                    } else {
                        Text("Guest account")
                    }
                }
            }

            if services?.isGuest == true {
                Button {
                    isShowingUpgrade = true
                } label: {
                    Label("Save my account", systemImage: "checkmark.seal")
                }
            }

            Button(role: .destructive) {
                if services?.isGuest == true {
                    isConfirmingGuestSignOut = true
                } else {
                    isConfirmingSignOut = true
                }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: services?.isGuest == true
                  ? "person.crop.circle.badge.exclamationmark"
                  : "person.crop.circle")
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
    }
}
