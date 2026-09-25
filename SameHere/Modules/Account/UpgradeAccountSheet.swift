//
//  UpgradeAccountSheet.swift
//  SameHere
//

import AuthFeature
import SwiftUI

/// Turns the signed-in guest into a saved account.
///
/// This is the packaged `RegisterView` in `.upgradeGuest` mode, so it is the same
/// form, validation and copy as sign-up — deliberately, because a separate
/// "convert" screen is how the two flows drift apart. What changes underneath is
/// the call: `linkAccount` attaches the email and password to the **existing**
/// user, keeping their id, so nothing they wrote as a guest is orphaned.
struct UpgradeAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let auth: AuthCoordinator
    @State private var viewModel: RegisterViewModel

    init(auth: AuthCoordinator) {
        self.auth = auth
        _viewModel = State(initialValue: auth.makeRegisterViewModel(mode: .upgradeGuest))
    }

    var body: some View {
        NavigationStack {
            RegisterView(viewModel: viewModel, theme: .sameHere) {
                BackgroundView()
            } logo: {
                BadgeIconView(
                    image: Image(systemName: "checkmark.seal.fill"),
                    size: 96,
                    padding: 26
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        // The upgrade lands the moment the user stops being a guest. With email
        // confirmation switched on in Supabase that does not happen here — they
        // stay a guest until they click the link, and RegisterView says so — so
        // this closes the sheet on success only, and leaves it open otherwise.
        .onChange(of: auth.isGuest) { _, isGuest in
            if !isGuest { dismiss() }
        }
    }
}
