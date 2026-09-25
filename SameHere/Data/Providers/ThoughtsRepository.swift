//
//  ThoughtsRepository.swift
//  SameHere
//

import Foundation

/// Reads and writes thoughts through PostgREST.
///
/// This is the layer the view models should talk to; they never see a URL, a
/// token or a DTO. It is a `struct` with no mutable state, so it is safe to hand
/// to anything and cheap to construct.
///
/// Every call goes through ``SupabaseClient``, which fetches a fresh access token
/// per request — see the note there about why holding a session is a trap.
nonisolated struct ThoughtsRepository: Sendable {

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// The feed: recent thoughts with their live vote counts.
    ///
    /// Two requests rather than one embedded query, on purpose. Embedding a *view*
    /// (`option_results`) relies on PostgREST inferring a relationship through the
    /// view definition, which works on some versions and quietly returns nothing on
    /// others. Two plain requests use only guaranteed behaviour, and the second one
    /// is a single indexed `in.()` lookup.
    ///
    /// - Parameters:
    ///   - topic: Restrict to one topic, or `nil` for everything.
    ///   - excludingAnswered: Skip thoughts the signed-in user already voted on.
    ///   - limit: Page size.
    func fetchThoughts(topic: String? = nil,
                       excludingAnswered: Bool = true,
                       limit: Int = 50) async throws -> [Thought] {
        var query: [URLQueryItem] = [
            .init(name: "select", value: "id,message,topic,created_at,author_id,is_ai_generated,profiles(id,name,email)"),
            .init(name: "order", value: "created_at.desc"),
            .init(name: "limit", value: String(limit))
        ]
        if let topic, !topic.isEmpty {
            query.append(.init(name: "topic", value: "eq.\(topic)"))
        }

        let rows: [ThoughtDTO] = try await client.get("thoughts", query: query)
        guard !rows.isEmpty else { return [] }

        var wanted = rows
        if excludingAnswered {
            let answered = try await fetchAnsweredThoughtIDs()
            if !answered.isEmpty {
                wanted = rows.filter { !answered.contains($0.id) }
            }
        }
        guard !wanted.isEmpty else { return [] }

        let options = try await fetchOptions(for: wanted.map(\.id))
        return wanted.map { $0.thought(options: options[$0.id] ?? []) }
    }

    /// Thoughts written by the signed-in user.
    ///
    /// Filtered by `author_id` rather than by an RLS policy, because `thoughts` is
    /// publicly readable — the policy would not narrow this for us.
    func fetchMyThoughts(userID: UUID, limit: Int = 100) async throws -> [Thought] {
        let query: [URLQueryItem] = [
            .init(name: "select", value: "id,message,topic,created_at,author_id,is_ai_generated,profiles(id,name,email)"),
            .init(name: "author_id", value: "eq.\(userID.uuidString.lowercased())"),
            .init(name: "order", value: "created_at.desc"),
            .init(name: "limit", value: String(limit))
        ]

        let rows: [ThoughtDTO] = try await client.get("thoughts", query: query)
        guard !rows.isEmpty else { return [] }

        let options = try await fetchOptions(for: rows.map(\.id))
        return rows.map { $0.thought(options: options[$0.id] ?? []) }
    }

    /// Ids of the thoughts the signed-in user has already answered.
    ///
    /// Reads `my_answers`, which filters on `auth.uid()` server-side — so this
    /// returns the right thing for a guest too, without the client having to say
    /// who it is.
    func fetchAnsweredThoughtIDs() async throws -> Set<UUID> {
        let rows: [MyAnswerDTO] = try await client.get(
            "my_answers",
            query: [.init(name: "select", value: "thought_id,option_id")]
        )
        return Set(rows.map(\.thoughtId))
    }

    /// Casts a vote.
    ///
    /// - Throws: ``SupabaseRequestError/duplicate`` when the user already voted on
    ///   this thought. That is the `unique (thought_id, user_id)` constraint doing
    ///   its job, so treat it as "already answered" and move on rather than as a
    ///   failure worth an alert.
    func vote(thoughtID: UUID, optionID: UUID, userID: UUID) async throws {
        try await client.insert(
            "answers",
            body: AnswerInsert(thoughtId: thoughtID, optionId: optionID, userId: userID)
        )
    }

    // MARK: - Options

    /// Vote counts for a set of thoughts, keyed by thought id and ordered by
    /// `position` so the options render in the order they were written.
    private func fetchOptions(for thoughtIDs: [UUID]) async throws -> [UUID: [OptionItem]] {
        let ids = thoughtIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
        let rows: [OptionResultDTO] = try await client.get(
            "option_results",
            query: [
                .init(name: "select", value: "option_id,thought_id,title,position,votes"),
                .init(name: "thought_id", value: "in.(\(ids))"),
                .init(name: "order", value: "position.asc")
            ]
        )
        return Dictionary(grouping: rows, by: \.thoughtId)
            .mapValues { $0.sorted { $0.position < $1.position }.map(\.option) }
    }
}
