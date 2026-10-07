//
//  AccountRepository.swift
//  SameHere
//

import Foundation

/// Account-level operations that live in the app's database rather than in
/// the auth package.
nonisolated struct AccountRepository: Sendable {

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Permanently deletes the signed-in user: their thoughts, their votes and
    /// the account itself. Runs `public.delete_my_account()` (see
    /// `supabase/delete_account.sql`), which only ever deletes the caller.
    ///
    /// The local session is still there afterwards — sign out right after.
    func deleteMyAccount() async throws {
        try await client.rpc("delete_my_account")
    }

    /// Whether this account already agreed to the community rules.
    func hasAcceptedTerms(userID: UUID) async throws -> Bool {
        let rows: [TermsAcceptanceDTO] = try await client.get(
            "profiles",
            query: [
                .init(name: "select", value: "terms_accepted_at"),
                .init(name: "id", value: "eq.\(userID.uuidString.lowercased())")
            ]
        )
        return rows.first?.termsAcceptedAt != nil
    }

    /// Records that this account agreed to the community rules, now.
    func acceptTerms(userID: UUID) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.update(
            "profiles",
            query: [.init(name: "id", value: "eq.\(userID.uuidString.lowercased())")],
            body: TermsAcceptanceDTO(termsAcceptedAt: now)
        )
    }
}
