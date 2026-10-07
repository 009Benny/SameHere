//
//  AppServices.swift
//  SameHere
//

import AuthFeature
import Foundation
import Observation

/// The app's composition root: everything that needs to exist once, built once,
/// in one place.
///
/// Constructing this is the only spot in the app that knows `SupabaseAuthService`
/// is the concrete auth provider, or that `ThoughtsRepository` is backed by
/// PostgREST. Everything dñwnstream receives what it needs.
///
/// It is created only after ``SupabaseConfig`` succeeds, which is why
/// ``AppCoordinator`` holds it as an optional and the views never do — by the
/// time a view can see it, it exists.
@Observable
@MainActor
final class AppServices {

    /// Project URL + anon key this build is pointed at.
    let configuration: SupabaseAuthConfiguration

    /// The concrete auth provider. Held as the concrete type because
    /// ``SupabaseAuthService/validAccessToken()`` — the thing the data layer needs
    /// — is deliberately not part of the `AuthService` protocol.
    let authService: SupabaseAuthService

    /// Owns the auth route and the session. Comes from the package; the app does
    /// not need a second login coordinator of its own.
    let auth: AuthCoordinator

    /// PostgREST transport.
    let client: SupabaseClient

    /// What the view models should talk to.
    let thoughts: ThoughtsRepository

    init(configuration: SupabaseAuthConfiguration) {
        self.configuration = configuration

        let authService = SupabaseAuthService(
            configuration: configuration,
            sessionStore: KeychainSessionStore()
        )
        self.authService = authService

        self.auth = AuthCoordinator(
            authService: authService,
            // Guests are the whole point: a first-time visitor should be able to
            // answer a thought before being asked for an email.
            policy: .guestFriendly
        )

        let client = SupabaseClient(
            projectURL: configuration.projectURL,
            anonKey: configuration.anonKey,
            // The data layer asks for a token per request rather than capturing
            // one. `validAccessToken()` refreshes when the current token is close
            // to expiry and coalesces concurrent callers into one refresh.
            tokenProvider: { try await authService.validAccessToken() }
        )
        self.client = client
        self.thoughts = ThoughtsRepository(client: client)
    }

    // MARK: - Who is signed in

    /// The active session. Useful for identity and display — **not** for holding
    /// on to `accessToken`, which expires in about an hour.
    var session: AuthSession? { auth.session }

    /// The signed-in person as the app's own model.
    ///
    /// `nil` only when signed out, so any screen behind the auth gate can safely
    /// treat it as present.
    var currentUser: User? {
        guard let user = auth.session?.user,
              let id = UUID(uuidString: user.id) else { return nil }
        return User(
            id: id,
            name: user.displayName ?? String(localized: "Guest"),
            email: user.email,
            isGuest: user.isAnonymous
        )
    }

    /// `true` when the signed-in user has no email attached yet.
    var isGuest: Bool { auth.isGuest }
}
