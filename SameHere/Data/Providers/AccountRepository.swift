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
}
