//
//  SignInRequired.swift
//  SameHere
//

import AuthFeature
import SwiftUI

/// Something a guest can't do until they sign in.
///
/// Guests can read and vote. Posting, reporting and blocking need an account:
/// a post needs someone to answer for it, and reports and blocks from throwaway
/// accounts are how moderation gets gamed.
enum GuestRestrictedAction: Identifiable {
    case createThought
    case report
    case block

    var id: Self { self }

    var message: LocalizedStringKey {
        switch self {
        case .createThought:
            "Guests can read and vote. To share your own thought, sign in or create an account."
        case .report:
            "To report a thought, sign in or create an account. This keeps reports from being abused."
        case .block:
            "To block someone, sign in or create an account."
        }
    }
}

extension View {
    /// Shows "Sign in to continue" with Cancel / Sign in whenever `action` is
    /// set. Sign in opens ``SignInSheet``; Cancel leaves the guest where they
    /// were, still a guest.
    ///
    /// ```swift
    /// if services?.isGuest == true { signInGate = .report } else { … }
    /// ```
    func guestSignInGate(_ action: Binding<GuestRestrictedAction?>) -> some View {
        modifier(GuestSignInGate(action: action))
    }
}

private struct GuestSignInGate: ViewModifier {
    @Binding var action: GuestRestrictedAction?
    @Environment(AppServices.self) private var services: AppServices?
    @State private var isShowingSignIn = false

    func body(content: Content) -> some View {
        content
            .alert(
                "Sign in to continue",
                isPresented: Binding(
                    get: { action != nil },
                    set: { if !$0 { action = nil } }
                ),
                presenting: action
            ) { _ in
                Button("Cancel", role: .cancel) { }
                Button("Sign in") { isShowingSignIn = true }
            } message: { action in
                Text(action.message)
            }
            .sheet(isPresented: $isShowingSignIn) {
                if let services {
                    SignInSheet(auth: services.auth)
                }
            }
    }
}

/// The login screen, shown over the app to someone who is currently a guest.
///
/// Not a sign-out: the guest session stays alive underneath, so Close puts them
/// straight back where they were. From here they can:
///
/// - **Log in** to an account they already have. The session switches to that
///   account; their guest votes stay in the database as anonymous answers.
/// - **Create an account.** The "register" link opens the *upgrade* form, not a
///   plain sign-up, so the email and password are attached to this guest and
///   everything they did as a guest comes with them.
///
/// "Continue as guest" is hidden — they already are one, and tapping it would
/// swap their account for a new, empty one.
struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    let auth: AuthCoordinator

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundView()
                    .ignoresSafeArea()
                screen
            }
            .animation(.snappy(duration: 0.32, extraBounce: 0), value: auth.route)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        // The coordinator's route is shared with the login flow at the root, so
        // start from — and leave it on — the login screen.
        .onAppear { auth.route = .login }
        .onDisappear { auth.route = .login }
        // Logged in, or upgraded: either way they're no longer a guest. With
        // email confirmation on, an upgrade waits for the link and the sheet
        // stays open showing RegisterView's "check your email".
        .onChange(of: auth.isGuest) { _, isGuest in
            if !isGuest { dismiss() }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch auth.route {
        case .login:
            LoginView(
                viewModel: auth.makeLoginViewModel(offersGuest: false),
                theme: .sameHere
            ) {
                Color.clear
            } logo: {
                BadgeIconView(image: Image("logo"), size: 110, padding: 0)
            }
            .id(AuthRoute.login)
            .transition(.move(edge: .leading).combined(with: .opacity))

        case .register, .upgradeGuest:
            RegisterView(
                viewModel: auth.makeRegisterViewModel(mode: .upgradeGuest),
                theme: .sameHere
            ) {
                Color.clear
            } logo: {
                BadgeIconView(
                    image: Image(systemName: "checkmark.seal.fill"),
                    size: 96,
                    padding: 26
                )
            }
            .id(AuthRoute.upgradeGuest)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
