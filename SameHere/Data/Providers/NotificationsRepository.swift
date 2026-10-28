//
//  NotificationsRepository.swift
//  SameHere
//

import Foundation

/// Saves this iPhone's push token so the digest Edge Function can reach it.
/// See `supabase/push_notifications.sql`.
nonisolated struct NotificationsRepository: Sendable {

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Saves the token for the signed-in user, or moves it to them if the
    /// same iPhone was registered by another account. Also how the chosen
    /// frequency reaches the server.
    func register(token: String,
                  environment: PushEnvironment,
                  locale: String,
                  frequency: DigestFrequency) async throws {
        try await client.rpc(
            "register_device_token",
            params: RegisterDeviceTokenParams(
                token: token,
                environment: environment.rawValue,
                locale: locale,
                frequency: frequency.rawValue
            )
        )
    }

    /// Stops pushes to this iPhone for the signed-in user. RLS only lets a
    /// user delete their own rows.
    func unregister(token: String) async throws {
        try await client.delete(
            "device_tokens",
            query: [.init(name: "token", value: "eq.\(token)")]
        )
    }
}

/// Which APNs server the token belongs to.
nonisolated enum PushEnvironment: String, Sendable {
    case sandbox
    case production

    /// Debug builds run from Xcode get sandbox tokens; TestFlight and App
    /// Store builds get production ones.
    static var current: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

/// How often the "new questions" push is sent. `off` keeps the token on the
/// server but the digest skips it.
nonisolated enum DigestFrequency: String, CaseIterable, Identifiable, Sendable {
    case off
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        }
    }
}

/// Arguments of `public.register_device_token(...)`.
nonisolated private struct RegisterDeviceTokenParams: Encodable, Sendable {
    let token: String
    let environment: String
    let locale: String
    let frequency: String

    enum CodingKeys: String, CodingKey {
        case token = "p_token"
        case environment = "p_environment"
        case locale = "p_locale"
        case frequency = "p_frequency"
    }
}
