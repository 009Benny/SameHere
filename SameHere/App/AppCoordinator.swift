//
//  AppCoordinator.swift
//  SameHere
//

import AuthFeature
import Foundation
import Observation

/// Decides what the app is showing, and owns the dependency graph behind it.
///
/// Note the division of labour, because it is easy to build one coordinator too
/// many here:
///
/// - `AuthFeature.AuthCoordinator` (inside ``AppServices``) drives the *login
///   flow*: which auth screen is on top, and what session came out of it.
/// - This type drives the *app*: configuration, launch, and the gate between the
///   auth flow and `SHTabView`.
///
/// There is no third coordinator, and no login logic here.
@Observable
@MainActor
final class AppCoordinator {

    /// What the root of the app should be showing.
    enum Phase: Equatable {
        /// Reading the Keychain and refreshing the token, if there is one.
        case launching
        /// The build has no usable Supabase credentials. Carries the fix.
        case misconfigured(String)
        /// There is a stored session but Supabase could not be reached to refresh
        /// it. Distinct from `signedOut` on purpose: the session is still on the
        /// device, and telling a returning guest to log in when they cannot would
        /// read as "my account is gone".
        case unreachable(String)
        case signedOut
        case signedIn
    }

    /// Built once configuration succeeds. `nil` before that and after a
    /// configuration failure.
    private(set) var services: AppServices?

    private var configurationError: String?
    private var hasCompletedInitialRestore = false
    /// Set when the user chooses to sign in anyway from the `unreachable` screen,
    /// so a stale restore error cannot trap them there.
    private var dismissedUnreachable = false

    /// Derived rather than stored, so it can never disagree with the auth
    /// coordinator about whether somebody is signed in.
    var phase: Phase {
        if let configurationError { return .misconfigured(configurationError) }
        guard let services, hasCompletedInitialRestore else { return .launching }
        if services.auth.isRestoring { return .launching }
        if services.auth.isAuthenticated { return .signedIn }
        if let restoreError = services.auth.restoreError, !dismissedUnreachable {
            return .unreachable(restoreError)
        }
        return .signedOut
    }

    // MARK: - Lifecycle

    /// Reads the configuration, builds the graph and restores any stored session.
    /// Safe to call more than once; only the first call does the work.
    func start() async {
        guard services == nil, configurationError == nil else { return }

        let configuration: SupabaseAuthConfiguration
        do {
            configuration = try SupabaseConfig.load()
        } catch {
            configurationError = error.localizedDescription
            return
        }

        let services = AppServices(configuration: configuration)
        self.services = services
        await services.auth.restore()
        hasCompletedInitialRestore = true
    }

    /// Leaves the `unreachable` screen for the login screen. Signing in still
    /// needs a connection, but the choice belongs to the user, not to us.
    func continueToSignIn() {
        dismissedUnreachable = true
    }

    /// Retries after a configuration or connection failure.
    func retry() async {
        dismissedUnreachable = false
        if configurationError != nil {
            configurationError = nil
            services = nil
            hasCompletedInitialRestore = false
            await start()
        } else {
            await services?.auth.restore()
        }
    }

    // MARK: - Session

    /// Signs out and returns to the auth flow.
    ///
    /// - Parameter forgettingCredentials: Also empties the Face ID vault.
    ///
    /// > Warning: For a guest this is irreversible — there is no password to come
    /// > back with. Every call site must confirm first; see `AccountMenu`.
    func signOut(forgettingCredentials: Bool = false) async {
        await services?.auth.signOut(forgetBiometricCredentials: forgettingCredentials)
    }
}
