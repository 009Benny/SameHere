//
//  PushNotifications.swift
//  SameHere
//

import Observation
import os
import UIKit
import UserNotifications

/// The "new questions" digest: the user's choice, the iOS permission, and
/// keeping this iPhone's token on the server.
///
/// One shared instance because `AppDelegate` — where iOS hands over the
/// token — lives outside the SwiftUI environment.
///
/// Flow: Profile → `setFrequency(_:)` asks iOS for permission (first time
/// only) → `registerForRemoteNotifications()` → iOS calls `AppDelegate` →
/// `didRegister(deviceToken:)` → saved for whoever is signed in. Signing in
/// with another account on the same iPhone moves the token to it.
@Observable
@MainActor
final class PushNotifications {

    static let shared = PushNotifications()

    /// What the user picked in Profile. Off until they opt in (App Store
    /// guideline 4.5.4: promotional pushes need explicit consent).
    private(set) var frequency: DigestFrequency

    /// The iOS permission. `.denied` can only be undone in Settings.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var isDeniedInSettings: Bool { authorizationStatus == .denied }

    private var isAuthorized: Bool {
        let allowed: [UNAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
        return allowed.contains(authorizationStatus)
    }

    private var deviceToken: String?
    private var repository: NotificationsRepository?

    private static let frequencyKey = "push.digestFrequency"
    private let logger = Logger(subsystem: "bennyreyes.dev.SameHere", category: "push")

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.frequencyKey)
        frequency = stored.flatMap(DigestFrequency.init(rawValue:)) ?? .off
    }

    // MARK: - Lifecycle

    /// At launch: the token can change, so ask for it again whenever the user
    /// has opted in and the permission is still there.
    func applicationDidFinishLaunching() async {
        await refreshAuthorizationStatus()
        if frequency != .off && isAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Re-read the permission; the user may have changed it in Settings.
    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus
    }

    /// Signed in: from now on the token is saved for this account.
    func attach(_ repository: NotificationsRepository) async {
        self.repository = repository
        await syncToken()
    }

    /// Signing out or deleting the account.
    ///
    /// - Parameter removingToken: Delete this iPhone's row first, so it stops
    ///   getting digests for the account. Pass `false` after deleting the
    ///   account — the row is already gone with it.
    func detach(removingToken: Bool = true) async {
        if removingToken, let repository, let deviceToken {
            do {
                try await repository.unregister(token: deviceToken)
            } catch {
                logger.error("Couldn't remove the push token: \(error.localizedDescription, privacy: .public)")
            }
        }
        repository = nil
    }

    // MARK: - The user's choice

    /// From Profile. The first time a digest is turned on, iOS asks for
    /// permission.
    ///
    /// - Returns: `false` when the permission was refused — the choice is not
    ///   applied and Profile points to Settings.
    @discardableResult
    func setFrequency(_ newValue: DigestFrequency) async -> Bool {
        if newValue != .off {
            if authorizationStatus == .notDetermined {
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])) ?? false
                await refreshAuthorizationStatus()
                guard granted else { return false }
            }
            guard isAuthorized else { return false }
        }

        frequency = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: Self.frequencyKey)

        if newValue != .off && deviceToken == nil {
            // The token arrives in `didRegister(deviceToken:)`, which saves it.
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            await syncToken()
        }
        return true
    }

    // MARK: - Token (from AppDelegate)

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        #if DEBUG
        // Handy for sending a test push from Apple's Push Notifications Console.
        logger.notice("APNs device token (sandbox): \(token, privacy: .public)")
        #endif
        Task { await syncToken() }
    }

    func didFailToRegister(_ error: Error) {
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Saves the token and the current choice for the signed-in user. Quietly
    /// gives up on failure; the next launch tries again.
    private func syncToken() async {
        guard let repository, let deviceToken else { return }
        do {
            try await repository.register(
                token: deviceToken,
                environment: .current,
                locale: Self.digestLocale,
                frequency: frequency
            )
        } catch {
            logger.error("Couldn't save the push token: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The language the digest is written in: the one the app is running in.
    private static var digestLocale: String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("es") == true ? "es" : "en"
    }
}

/// Receives the push token from iOS and shows pushes that arrive while the app
/// is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await PushNotifications.shared.applicationDidFinishLaunching() }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotifications.shared.didFailToRegister(error)
    }

    /// Show the banner even with the app open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
