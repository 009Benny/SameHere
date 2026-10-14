//
//  ModelTests.swift
//  SameHereTests
//

import Foundation
import Testing
@testable import SameHere

struct ModelTests {

    @Test func topicRawValuesMatchTheDatabaseFormat() {
        #expect(Topic.allCases.map(\.rawValue) == [
            "GENERAL", "TECNOLOGIA", "ENTRETENIMIENTO", "DEPORTES",
            "COMIDA", "VIAJES", "RELACIONES", "TRABAJO"
        ])
        // Stored upper case with no accents, like the seeded questions.
        for topic in Topic.allCases {
            #expect(topic.rawValue == topic.rawValue.uppercased())
            #expect(topic.rawValue.folding(options: .diacriticInsensitive, locale: nil) == topic.rawValue)
            #expect(!topic.title.isEmpty)
        }
    }

    @Test func reportReasonsMatchTheCheckConstraint() {
        #expect(ReportReason.allCases.map(\.rawValue) == ["offensive", "harassment", "sexual", "spam", "other"])
        for reason in ReportReason.allCases { #expect(!reason.title.isEmpty) }
    }

    @Test func thoughtTotalSumsEveryCounter() {
        let thought = Thought(
            id: UUID(), user: .seeded(id: UUID()), message: "Q",
            options: [OptionItem(id: UUID(), title: "A", counter: 7),
                      OptionItem(id: UUID(), title: "B", counter: 3)],
            topic: "GENERAL"
        )
        #expect(thought.getTotal() == 10)
    }

    @Test func thoughtWithoutOptionsHasZeroTotal() {
        let thought = Thought(id: UUID(), user: .seeded(id: UUID()), message: "Q", options: [], topic: "GENERAL")
        #expect(thought.getTotal() == 0)
    }

    @Test func seededUserIsNamedSameHereAndIsNotAGuest() {
        let user = User.seeded(id: UUID())
        #expect(user.name == "Same Here")
        #expect(user.email == nil)
        #expect(user.isGuest == false)
    }

    // MARK: - DTO mapping

    @Test func seededThoughtDecodesWithNoAuthorAndNoSourceURL() throws {
        let dto = try JSONDecoder.supabase.decode(ThoughtDTO.self, from: Data(Fixture.thoughtJSON(1).utf8))
        let thought = dto.thought(options: [])

        #expect(thought.id == Fixture.id(1))
        #expect(thought.authorID == nil)
        #expect(thought.sourceURL == nil)
        #expect(thought.user.name == "Same Here")
    }

    @Test func seededThoughtKeepsItsSourceLink() throws {
        let json = Fixture.thoughtJSON(2, link: "https://example.com/article")
        let thought = try JSONDecoder.supabase.decode(ThoughtDTO.self, from: Data(json.utf8)).thought(options: [])
        #expect(thought.sourceURL == URL(string: "https://example.com/article"))
    }

    @Test func communityThoughtUsesTheEmbeddedProfile() throws {
        let json = """
        {"id":"\(Fixture.id(3).uuidString)","message":"Hi","topic":"GENERAL",
         "created_at":"2026-08-04T10:00:00+00:00","author_id":"\(Fixture.userA.uuidString)",
         "is_ai_generated":false,"source_link":null,
         "profiles":{"id":"\(Fixture.userA.uuidString)","name":"Benny","email":"b@x.com","is_guest":false}}
        """
        let thought = try JSONDecoder.supabase.decode(ThoughtDTO.self, from: Data(json.utf8)).thought(options: [])

        #expect(thought.user.name == "Benny")
        #expect(thought.user.email == "b@x.com")
        #expect(thought.authorID == Fixture.userA)
    }

    @Test func keepsTheRawTimestampForPagination() throws {
        let dto = try JSONDecoder.supabase.decode(ThoughtDTO.self, from: Data(Fixture.thoughtJSON(1).utf8))
        #expect(dto.createdAt == "2026-08-04T10:00:00.123456+00:00")
    }

    @Test func optionResultMapsVotesToCounter() throws {
        let json = #"{"option_id":"\#(Fixture.id(11).uuidString)","thought_id":"\#(Fixture.id(1).uuidString)","title":"Yes","position":0,"votes":42}"#
        let dto = try JSONDecoder.supabase.decode(OptionResultDTO.self, from: Data(json.utf8))
        #expect(dto.option == OptionItem(id: Fixture.id(11), title: "Yes", counter: 42))
    }

    @Test func profileWithoutGuestFlagIsNotAGuest() throws {
        let json = #"{"id":"\#(Fixture.userA.uuidString)","name":"N","email":null}"#
        let dto = try JSONDecoder.supabase.decode(ProfileDTO.self, from: Data(json.utf8))
        #expect(dto.user.isGuest == false)
    }

    @Test func insertPayloadsUseSnakeCaseColumns() throws {
        let body = try JSONEncoder.supabase.encode(
            AnswerInsert(thoughtId: Fixture.id(1), optionId: Fixture.id(2), userId: Fixture.userA)
        )
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(object.keys) == ["thought_id", "option_id", "user_id"])

        let thought = try JSONEncoder.supabase.encode(
            ThoughtInsert(authorId: Fixture.userA, message: "m", topic: "GENERAL", isAiGenerated: false)
        )
        let thoughtObject = try #require(JSONSerialization.jsonObject(with: thought) as? [String: Any])
        #expect(thoughtObject["is_ai_generated"] as? Bool == false)
        #expect(thoughtObject["author_id"] != nil)
    }

    // MARK: - Timestamps

    @Test(arguments: [
        "2026-08-04T10:00:00+00:00",
        "2026-08-04T10:00:00Z",
        "2026-08-04T10:00:00.1+00:00",
        "2026-08-04T10:00:00.123+00:00",
        "2026-08-04T10:00:00.123456+00:00",
        "2026-08-04T10:00:00.999999Z"
    ])
    func parsesEveryFractionLengthPostgresEmits(raw: String) {
        #expect(PostgresTimestamp.parse(raw) != nil)
    }

    @Test func fractionalDigitsAreTruncatedNotRounded() throws {
        let whole = try #require(PostgresTimestamp.parse("2026-08-04T10:00:00+00:00"))
        let parsed = try #require(PostgresTimestamp.parse("2026-08-04T10:00:00.999999+00:00"))
        #expect(parsed.timeIntervalSince(whole) > 0.99)
        #expect(parsed.timeIntervalSince(whole) < 1.0)
    }

    @Test func rejectsGarbage() {
        #expect(PostgresTimestamp.parse("not a date") == nil)
        #expect(PostgresTimestamp.parse("") == nil)
    }
}
