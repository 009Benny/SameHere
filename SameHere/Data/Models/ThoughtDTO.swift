//
//  ThoughtDTO.swift
//  SameHere
//
//  Wire shapes for the Supabase tables, kept separate from the domain models so
//  `Thought`, `OptionItem` and `User` never have to care what the columns are
//  called. Decoded with `JSONDecoder.supabase`, which converts snake_case, so no
//  CodingKeys are needed.
//

import Foundation

/// A row from `public.thoughts`, optionally with its author embedded.
nonisolated struct ThoughtDTO: Decodable, Sendable {
    let id: UUID
    let message: String
    let topic: String
    /// Kept as Postgres sent it (microsecond precision) because the feed uses
    /// it as a pagination cursor, and a round trip through `Date` would lose
    /// digits and break the `eq` comparison. Use `PostgresTimestamp.parse` if a
    /// `Date` is ever needed for display.
    let createdAt: String?
    let authorId: UUID?
    let isAiGenerated: Bool?
    /// Embedded via the `author_id → profiles.id` foreign key.
    let profiles: ProfileDTO?
}

/// A row from `public.profiles`.
nonisolated struct ProfileDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let email: String?
    let isGuest: Bool?

    var user: User {
        User(id: id, name: name, email: email, isGuest: isGuest ?? false)
    }
}

/// A row from the `public.option_results` view — `seed_votes` plus real votes.
///
/// Always read counters from this view rather than `options` directly, or the
/// percentages ignore everything real users have voted.
nonisolated struct OptionResultDTO: Decodable, Sendable {
    let optionId: UUID
    let thoughtId: UUID
    let title: String
    let position: Int
    let votes: Int

    var option: OptionItem {
        OptionItem(id: optionId, title: title, counter: votes)
    }
}

/// A row from the `public.my_answers` view: what the signed-in user already voted
/// on. The view filters on `auth.uid()`, so it returns nothing without a session —
/// which is exactly why the app needs one before it can load the feed properly.
nonisolated struct MyAnswerDTO: Decodable, Sendable {
    let thoughtId: UUID
    let optionId: UUID
}

/// Insert payload for `public.answers`. `userId` must equal `auth.uid()` or the
/// RLS policy refuses the write.
nonisolated struct AnswerInsert: Encodable, Sendable {
    let thoughtId: UUID
    let optionId: UUID
    let userId: UUID
}

extension ThoughtDTO {
    /// Combines a thought row with its options into the model the views use.
    func thought(options: [OptionItem]) -> Thought {
        Thought(
            id: id,
            user: profiles?.user ?? .seeded(id: id),
            message: message,
            options: options,
            topic: topic
        )
    }
}
