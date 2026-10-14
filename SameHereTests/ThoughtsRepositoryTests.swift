//
//  ThoughtsRepositoryTests.swift
//  SameHereTests
//

import Foundation
import Testing
@testable import SameHere

struct ThoughtsRepositoryTests {

    // MARK: - Feed

    @Test func feedPageCombinesThoughtsWithTheirOptionsInOrder() async throws {
        let server = Fixture.feedServer(thoughts: [1, 2])
        let repo = ThoughtsRepository(client: server.makeClient())

        let page = try await repo.fetchFeedPage(after: nil)

        #expect(page.thoughts.map(\.id) == [Fixture.id(1), Fixture.id(2)])
        #expect(page.thoughts[0].options.map(\.title) == ["Yes", "No"])
        #expect(page.thoughts[0].options.map(\.counter) == [3, 1])
        #expect(page.thoughts[0].getTotal() == 4)
    }

    @Test func shortPageMeansTheFeedEnded() async throws {
        let server = Fixture.feedServer(thoughts: [1, 2])
        let page = try await ThoughtsRepository(client: server.makeClient()).fetchFeedPage(after: nil, pageSize: 10)
        #expect(page.nextCursor == nil)
    }

    @Test func fullPageReturnsACursorAtItsLastRow() async throws {
        let server = Fixture.feedServer(thoughts: [1, 2, 3])
        let page = try await ThoughtsRepository(client: server.makeClient()).fetchFeedPage(after: nil, pageSize: 3)

        #expect(page.nextCursor == FeedCursor(createdAt: "2026-08-04T10:00:00.123456+00:00", id: Fixture.id(3)))
    }

    @Test func skipsThoughtsAlreadyAnsweredOrReported() async throws {
        let server = Fixture.feedServer(thoughts: [1, 2, 3], answered: [Fixture.id(1)], reported: [Fixture.id(3)])
        let page = try await ThoughtsRepository(client: server.makeClient()).fetchFeedPage(after: nil)

        #expect(page.thoughts.map(\.id) == [Fixture.id(2)])
    }

    @Test func emptyFeedReturnsAnEmptyPageWithoutAskingForOptions() async throws {
        let server = Fixture.feedServer(thoughts: [])
        let page = try await ThoughtsRepository(client: server.makeClient()).fetchFeedPage(after: nil)

        #expect(page.thoughts.isEmpty)
        #expect(server.requests("GET", "option_results").isEmpty)
    }

    @Test func hidesOwnAndBlockedAuthorsButKeepsSeededThoughts() async throws {
        let server = Fixture.feedServer(thoughts: [1], blocked: [Fixture.userB])
        let repo = ThoughtsRepository(client: server.makeClient())

        _ = try await repo.fetchFeedPage(after: nil, excludingAuthor: Fixture.userA)

        let filter = try #require(server.requests("GET", "thoughts").first?.query["and"])
        // NULL authors (seeded questions) are kept explicitly...
        #expect(filter.contains("author_id.is.null"))
        // ...while both the viewer and the blocked person are excluded.
        #expect(filter.contains(Fixture.userA.uuidString.lowercased()))
        #expect(filter.contains(Fixture.userB.uuidString.lowercased()))
        #expect(filter.contains("author_id.not.in."))
    }

    @Test func noAuthorFilterWhenNothingIsHidden() async throws {
        let server = Fixture.feedServer(thoughts: [1])
        _ = try await ThoughtsRepository(client: server.makeClient()).fetchFeedPage(after: nil)

        #expect(server.requests("GET", "thoughts").first?.query["and"] == nil)
    }

    @Test func cursorBecomesAKeysetFilterWithAQuotedTimestamp() async throws {
        let server = Fixture.feedServer(thoughts: [])
        let cursor = FeedCursor(createdAt: "2026-08-04T10:00:00.123456+00:00", id: Fixture.id(5))

        _ = try await ThoughtsRepository(client: server.makeClient()).fetchFeedPage(after: cursor)

        let request = try #require(server.requests("GET", "thoughts").first)
        let filter = try #require(request.query["and"])
        #expect(filter.contains(#"created_at.lt."2026-08-04T10:00:00.123456+00:00""#))
        #expect(filter.contains(#"created_at.eq."2026-08-04T10:00:00.123456+00:00""#))
        #expect(filter.contains("id.lt.\(Fixture.id(5).uuidString.lowercased())"))
        // The "+" must survive the trip as %2B or the server reads a space.
        #expect(request.url.absoluteString.contains("%2B00:00"))
        #expect(request.query["order"] == "created_at.desc,id.desc")
    }

    @Test func topicFilterIsSentWhenGiven() async throws {
        let server = Fixture.feedServer(thoughts: [])
        _ = try await ThoughtsRepository(client: server.makeClient()).fetchFeedPage(after: nil, topic: "DEPORTES")
        #expect(server.requests("GET", "thoughts").first?.query["topic"] == "eq.DEPORTES")
    }

    @Test func keepsReadingWhenAWholePageWasAlreadyAnswered() async throws {
        // Page size 2: the first request is entirely answered, so the
        // repository must go on to the next one instead of returning empty.
        let server = Fixture.feedServer(thoughts: [], answered: [Fixture.id(1), Fixture.id(2)])
        server.on("GET", "thoughts") { request in
            if request.query["and"]?.contains("created_at.lt") == true {
                return .init(body: Fixture.thoughtsJSON([3]))
            }
            return .init(body: Fixture.thoughtsJSON([1, 2]))
        }
        server.on("GET", "option_results", json: Fixture.optionsJSON(for: [3]))

        let page = try await ThoughtsRepository(client: server.makeClient()).fetchFeedPage(after: nil, pageSize: 2)

        #expect(page.thoughts.map(\.id) == [Fixture.id(3)])
        #expect(server.requests("GET", "thoughts").count == 2)
    }

    @Test func feedErrorsPropagate() async {
        let server = Fixture.feedServer(thoughts: [1])
        server.on("GET", "thoughts", status: 500, json: #"{"message":"boom"}"#)
        await #expect(throws: SupabaseRequestError.self) {
            _ = try await ThoughtsRepository(client: server.makeClient()).fetchFeedPage(after: nil)
        }
    }

    @Test func neverAsksForAuthorEmails() async throws {
        let server = Fixture.feedServer(thoughts: [1])
        let repo = ThoughtsRepository(client: server.makeClient())

        _ = try await repo.fetchFeedPage(after: nil, excludingAuthor: Fixture.userA)
        _ = try await repo.fetchMyThoughts(userID: Fixture.userA)
        _ = try await repo.fetchThoughts()

        let selects = server.requests("GET", "thoughts").compactMap { $0.query["select"] }
        #expect(selects.count == 3)
        for select in selects { #expect(!select.contains("email")) }
    }

    // MARK: - My thoughts

    @Test func myThoughtsAreFilteredByAuthor() async throws {
        let server = Fixture.feedServer(thoughts: [1, 2])
        let mine = try await ThoughtsRepository(client: server.makeClient()).fetchMyThoughts(userID: Fixture.userA)

        #expect(mine.count == 2)
        let request = try #require(server.requests("GET", "thoughts").first)
        #expect(request.query["author_id"] == "eq.\(Fixture.userA.uuidString.lowercased())")
        #expect(request.query["order"] == "created_at.desc")
    }

    @Test func myThoughtsEmptyReturnsEmpty() async throws {
        let server = Fixture.feedServer(thoughts: [])
        #expect(try await ThoughtsRepository(client: server.makeClient()).fetchMyThoughts(userID: Fixture.userA).isEmpty)
    }

    // MARK: - Creating

    @Test func createThoughtInsertsTheThoughtThenItsOptionsInOrder() async throws {
        let server = StubServer()
        server.on("POST", "thoughts", status: 201, json: #"[{"id":"\#(Fixture.id(9).uuidString)"}]"#)
        server.on("POST", "options", status: 201, json: "")

        let id = try await ThoughtsRepository(client: server.makeClient())
            .createThought(message: "Do you…?", topic: "GENERAL", options: ["Yes", "No", "Maybe"], authorID: Fixture.userA)

        #expect(id == Fixture.id(9))

        let thoughtBody = try #require(server.requests("POST", "thoughts").first?.bodyJSON as? [String: Any])
        #expect(thoughtBody["message"] as? String == "Do you…?")
        #expect(thoughtBody["is_ai_generated"] as? Bool == false)
        #expect(thoughtBody["author_id"] as? String == Fixture.userA.uuidString)

        let optionRows = try #require(server.requests("POST", "options").first?.bodyJSON as? [[String: Any]])
        #expect(optionRows.map { $0["title"] as? String } == ["Yes", "No", "Maybe"])
        #expect(optionRows.map { $0["position"] as? Int } == [0, 1, 2])
        #expect(optionRows.allSatisfy { $0["thought_id"] as? String == Fixture.id(9).uuidString })
    }

    @Test func createThoughtRemovesTheThoughtWhenOptionsFail() async throws {
        let server = StubServer()
        server.on("POST", "thoughts", status: 201, json: #"[{"id":"\#(Fixture.id(9).uuidString)"}]"#)
        server.on("POST", "options", status: 500, json: #"{"message":"nope"}"#)
        server.on("DELETE", "thoughts", status: 204, json: "")

        await #expect(throws: SupabaseRequestError.self) {
            try await ThoughtsRepository(client: server.makeClient())
                .createThought(message: "Q", topic: "GENERAL", options: ["A", "B"], authorID: Fixture.userA)
        }

        let deletes = server.requests("DELETE", "thoughts")
        #expect(deletes.count == 1)
        #expect(deletes.first?.query["id"] == "eq.\(Fixture.id(9).uuidString.lowercased())")
    }

    @Test func createThoughtSurfacesBannedWordsAsContentRejected() async {
        let server = StubServer()
        server.on("POST", "thoughts", status: 400, json: #"{"code":"23514","message":"banned"}"#)

        do {
            try await ThoughtsRepository(client: server.makeClient())
                .createThought(message: "x", topic: "GENERAL", options: ["A", "B"], authorID: Fixture.userA)
            Issue.record("Expected a throw")
        } catch {
            #expect(error as? SupabaseRequestError == .contentRejected)
            #expect(server.requests("POST", "options").isEmpty)
        }
    }

    @Test func createThoughtFailsCleanlyWhenNoIdComesBack() async {
        let server = StubServer()
        server.on("POST", "thoughts", status: 201, json: "[]")
        await #expect(throws: SupabaseRequestError.self) {
            try await ThoughtsRepository(client: server.makeClient())
                .createThought(message: "x", topic: "GENERAL", options: ["A", "B"], authorID: Fixture.userA)
        }
    }

    // MARK: - Voting

    @Test func voteSendsThoughtOptionAndUser() async throws {
        let server = StubServer()
        server.on("POST", "answers", status: 201, json: "")

        try await ThoughtsRepository(client: server.makeClient())
            .vote(thoughtID: Fixture.id(1), optionID: Fixture.id(11), userID: Fixture.userA)

        let body = try #require(server.requests("POST", "answers").first?.bodyJSON as? [String: Any])
        #expect(body["thought_id"] as? String == Fixture.id(1).uuidString)
        #expect(body["option_id"] as? String == Fixture.id(11).uuidString)
        #expect(body["user_id"] as? String == Fixture.userA.uuidString)
    }

    @Test func votingTwiceThrowsDuplicate() async {
        let server = StubServer()
        server.on("POST", "answers", status: 409, json: #"{"code":"23505","message":"dup"}"#)
        do {
            try await ThoughtsRepository(client: server.makeClient())
                .vote(thoughtID: Fixture.id(1), optionID: Fixture.id(11), userID: Fixture.userA)
            Issue.record("Expected a throw")
        } catch {
            #expect(error as? SupabaseRequestError == .duplicate)
        }
    }

    @Test func optionResultsComeFromTheViewWithRealCounts() async throws {
        let server = StubServer()
        server.on("GET", "option_results", json: Fixture.optionsJSON(for: [1], votes: (10, 5)))

        let options = try await ThoughtsRepository(client: server.makeClient()).fetchOptionResults(thoughtID: Fixture.id(1))

        #expect(options.map(\.counter) == [10, 5])
        #expect(server.requests("GET", "option_results").first?.query["thought_id"] == "in.(\(Fixture.id(1).uuidString.lowercased()))")
    }

    // MARK: - Moderation

    @Test func reportSendsTheReasonRawValue() async throws {
        let server = StubServer()
        server.on("POST", "reports", status: 201, json: "")

        try await ThoughtsRepository(client: server.makeClient())
            .report(thoughtID: Fixture.id(1), reason: .harassment, reporterID: Fixture.userA)

        let body = try #require(server.requests("POST", "reports").first?.bodyJSON as? [String: Any])
        #expect(body["reason"] as? String == "harassment")
        #expect(body["reporter_id"] as? String == Fixture.userA.uuidString)
    }

    @Test func reportingTwiceIsNotAnError() async throws {
        let server = StubServer()
        server.on("POST", "reports", status: 409, json: #"{"code":"23505","message":"dup"}"#)
        try await ThoughtsRepository(client: server.makeClient())
            .report(thoughtID: Fixture.id(1), reason: .spam, reporterID: Fixture.userA)
    }

    @Test func otherReportFailuresStillThrow() async {
        let server = StubServer()
        server.on("POST", "reports", status: 500, json: #"{"message":"boom"}"#)
        await #expect(throws: SupabaseRequestError.self) {
            try await ThoughtsRepository(client: server.makeClient())
                .report(thoughtID: Fixture.id(1), reason: .spam, reporterID: Fixture.userA)
        }
    }

    @Test func blockSendsBothIdsAndIgnoresDuplicates() async throws {
        let server = StubServer()
        server.on("POST", "blocks", status: 201, json: "")
        let repo = ThoughtsRepository(client: server.makeClient())

        try await repo.block(userID: Fixture.userB, blockerID: Fixture.userA)
        let body = try #require(server.requests("POST", "blocks").first?.bodyJSON as? [String: Any])
        #expect(body["blocker_id"] as? String == Fixture.userA.uuidString)
        #expect(body["blocked_id"] as? String == Fixture.userB.uuidString)

        server.on("POST", "blocks", status: 409, json: #"{"code":"23505","message":"dup"}"#)
        try await repo.block(userID: Fixture.userB, blockerID: Fixture.userA)
    }

    @Test func fetchesAnsweredReportedAndBlockedIDs() async throws {
        let server = Fixture.feedServer(thoughts: [], answered: [Fixture.id(1)], reported: [Fixture.id(2)], blocked: [Fixture.userB])
        let repo = ThoughtsRepository(client: server.makeClient())

        #expect(try await repo.fetchAnsweredThoughtIDs() == [Fixture.id(1)])
        #expect(try await repo.fetchReportedThoughtIDs() == [Fixture.id(2)])
        #expect(try await repo.fetchBlockedUserIDs() == [Fixture.userB])
    }
}

// MARK: - Account

struct AccountRepositoryTests {

    @Test func deleteMyAccountCallsTheRPC() async throws {
        let server = StubServer()
        server.on("POST", "rpc/delete_my_account", status: 204, json: "")
        try await AccountRepository(client: server.makeClient()).deleteMyAccount()
        #expect(server.requests("POST", "rpc/delete_my_account").count == 1)
    }

    @Test func deleteMyAccountPropagatesFailures() async {
        let server = StubServer()
        server.on("POST", "rpc/delete_my_account", status: 500, json: #"{"message":"boom"}"#)
        await #expect(throws: SupabaseRequestError.self) {
            try await AccountRepository(client: server.makeClient()).deleteMyAccount()
        }
    }

    @Test func hasAcceptedTermsIsTrueOnlyWithATimestamp() async throws {
        let server = StubServer()
        let repo = AccountRepository(client: server.makeClient())

        server.on("GET", "profiles", json: #"[{"terms_accepted_at":"2026-08-04T10:00:00+00:00"}]"#)
        #expect(try await repo.hasAcceptedTerms(userID: Fixture.userA) == true)

        server.on("GET", "profiles", json: #"[{"terms_accepted_at":null}]"#)
        #expect(try await repo.hasAcceptedTerms(userID: Fixture.userA) == false)

        server.on("GET", "profiles", json: "[]")
        #expect(try await repo.hasAcceptedTerms(userID: Fixture.userA) == false)
    }

    @Test func acceptTermsPatchesOnlyThisProfile() async throws {
        let server = StubServer()
        server.on("PATCH", "profiles", status: 204, json: "")
        try await AccountRepository(client: server.makeClient()).acceptTerms(userID: Fixture.userA)

        let request = try #require(server.requests("PATCH", "profiles").first)
        #expect(request.query["id"] == "eq.\(Fixture.userA.uuidString.lowercased())")
        let stamp = (request.bodyJSON as? [String: Any])?["terms_accepted_at"] as? String
        #expect(stamp.flatMap(PostgresTimestamp.parse) != nil)
    }
}
