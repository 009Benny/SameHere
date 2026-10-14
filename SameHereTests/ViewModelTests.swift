//
//  ViewModelTests.swift
//  SameHereTests
//
//  The app target defaults to MainActor, so its view models are main-actor
//  types and the tests that drive them are too.
//

import Foundation
import Testing
@testable import SameHere

@MainActor
struct HomeViewModelTests {

    private func makeModel(_ server: StubServer, user: UUID = Fixture.userA) -> HomeViewModel {
        let model = HomeViewModel()
        model.configure(repository: ThoughtsRepository(client: server.makeClient()), currentUserID: user)
        return model
    }

    @Test func withoutABackendItFallsBackToMockData() async {
        let model = HomeViewModel()
        await model.loadData()
        #expect(!model.thoughts.isEmpty)
    }

    @Test func loadPutsTheNewestThoughtOnTopOfTheStack() async {
        let model = makeModel(Fixture.feedServer(thoughts: [1, 2, 3]))
        await model.loadData()

        // The last element is the top card, and feeds arrive newest-first.
        #expect(model.thoughts.map(\.id) == [Fixture.id(3), Fixture.id(2), Fixture.id(1)])
        #expect(model.errorMessage == nil)
        #expect(model.isLoading == false)
    }

    @Test func reloadingNeverShowsTheSameCardTwice() async {
        let model = makeModel(Fixture.feedServer(thoughts: [1, 2]))
        await model.loadData()
        await model.loadData()

        #expect(model.thoughts.count == 2)
        #expect(Set(model.thoughts.map(\.id)).count == 2)
    }

    @Test func feedFailureShowsAnErrorAndKeepsTheStack() async {
        let server = Fixture.feedServer(thoughts: [1])
        server.on("GET", "my_answers", error: .notConnectedToInternet)
        let model = makeModel(server)
        await model.loadData()

        #expect(model.thoughts.isEmpty)
        #expect(model.errorMessage == SupabaseRequestError.offline.errorDescription)
        #expect(model.isLoading == false)
    }

    @Test func ownThoughtsAreExcludedFromTheRequest() async {
        let server = Fixture.feedServer(thoughts: [1])
        let model = makeModel(server, user: Fixture.userA)
        await model.loadData()

        let filter = server.requests("GET", "thoughts").first?.query["and"]
        #expect(filter?.contains(Fixture.userA.uuidString.lowercased()) == true)
    }

    @Test func answeringSavesTheVoteThenReturnsFreshCounts() async throws {
        let server = Fixture.feedServer(thoughts: [1])
        server.on("POST", "answers", status: 201, json: "")
        let model = makeModel(server)
        await model.loadData()
        let thought = try #require(model.thoughts.last)

        // After the vote the server reports the new totals.
        server.on("GET", "option_results", json: Fixture.optionsJSON(for: [1], votes: (4, 1)))
        let options = try await model.answer(thought, option: Fixture.id(11))

        #expect(options.map(\.counter) == [4, 1])
        // The vote is written before the counts are read, so they include it.
        let order = server.requests.map { "\($0.method) \($0.path)" }
        let vote = try #require(order.lastIndex(of: "POST /rest/v1/answers"))
        let fetch = try #require(order.lastIndex(of: "GET /rest/v1/option_results"))
        #expect(vote < fetch)
    }

    @Test func answeringAnAlreadyAnsweredThoughtIsNotAnError() async throws {
        let server = Fixture.feedServer(thoughts: [1])
        server.on("POST", "answers", status: 409, json: #"{"code":"23505","message":"dup"}"#)
        let model = makeModel(server)
        await model.loadData()
        let thought = try #require(model.thoughts.last)

        let options = try await model.answer(thought, option: Fixture.id(11))
        #expect(options.count == 2)
    }

    @Test func aFailedVoteThrowsSoTheUserCanRetry() async throws {
        let server = Fixture.feedServer(thoughts: [1])
        server.on("POST", "answers", status: 500, json: #"{"message":"boom"}"#)
        let model = makeModel(server)
        await model.loadData()
        let thought = try #require(model.thoughts.last)

        await #expect(throws: SupabaseRequestError.self) {
            _ = try await model.answer(thought, option: Fixture.id(11))
        }
    }

    @Test func previewAnswerCountsTheVoteLocally() async throws {
        let model = HomeViewModel()
        let option = OptionItem(id: UUID(), title: "A", counter: 5)
        let other = OptionItem(id: UUID(), title: "B", counter: 2)
        let thought = Thought(id: UUID(), user: .seeded(id: UUID()), message: "Q", options: [option, other], topic: "GENERAL")

        let result = try await model.answer(thought, option: option.id)
        #expect(result.map(\.counter) == [6, 2])
    }

    @Test func reportingRemovesTheCardAndTellsTheServer() async throws {
        let server = Fixture.feedServer(thoughts: [1, 2])
        server.on("POST", "reports", status: 201, json: "")
        let model = makeModel(server)
        await model.loadData()
        let top = try #require(model.thoughts.last)

        try await model.report(top, reason: .spam)

        #expect(!model.thoughts.contains(top))
        #expect(server.requests("POST", "reports").count == 1)
    }

    @Test func aFailedReportKeepsTheCard() async throws {
        let server = Fixture.feedServer(thoughts: [1])
        server.on("POST", "reports", status: 500, json: #"{"message":"boom"}"#)
        let model = makeModel(server)
        await model.loadData()
        let top = try #require(model.thoughts.last)

        await #expect(throws: SupabaseRequestError.self) { try await model.report(top, reason: .spam) }
        #expect(model.thoughts.contains(top))
    }

    @Test func blockingRemovesEveryCardByThatAuthor() async throws {
        let server = StubServer()
        server.on("GET", "my_answers"); server.on("GET", "reports"); server.on("GET", "blocks")
        server.on("GET", "thoughts", json: "[" + [
            Fixture.thoughtJSON(1, author: Fixture.userB),
            Fixture.thoughtJSON(2, author: Fixture.userB),
            Fixture.thoughtJSON(3)
        ].joined(separator: ",") + "]")
        server.on("GET", "option_results", json: Fixture.optionsJSON(for: [1, 2, 3]))
        server.on("POST", "blocks", status: 201, json: "")
        let model = makeModel(server)
        await model.loadData()
        let blockedCard = try #require(model.thoughts.first { $0.authorID == Fixture.userB })

        try await model.blockAuthor(of: blockedCard)

        #expect(model.thoughts.map(\.id) == [Fixture.id(3)])
        #expect(server.requests("POST", "blocks").count == 1)
    }

    @Test func blockingASeededThoughtDoesNothing() async throws {
        let server = Fixture.feedServer(thoughts: [1])
        let model = makeModel(server)
        await model.loadData()
        let seeded = try #require(model.thoughts.last)

        try await model.blockAuthor(of: seeded)

        #expect(model.thoughts.count == 1)
        #expect(server.requests("POST", "blocks").isEmpty)
    }

    @Test func removeFromStackDropsOnlyThatCard() async throws {
        let model = makeModel(Fixture.feedServer(thoughts: [1, 2, 3]))
        await model.loadData()
        let top = try #require(model.thoughts.last)

        model.removeFromStack(top)
        #expect(model.thoughts.count == 2)
        #expect(!model.thoughts.contains(top))

        model.swipeItem(try #require(model.thoughts.last), direction: .left)
        #expect(model.thoughts.count == 1)
    }
}

@MainActor
struct MyThoughtsViewModelTests {

    private func makeModel(_ server: StubServer) -> MyThoughtsViewModel {
        let model = MyThoughtsViewModel()
        model.configure(repository: ThoughtsRepository(client: server.makeClient()), currentUserID: Fixture.userA)
        return model
    }

    @Test func loadsOnlyTheUsersOwnThoughts() async {
        let server = Fixture.feedServer(thoughts: [1, 2])
        let model = makeModel(server)
        await model.loadData()

        #expect(model.thoughts.count == 2)
        #expect(server.requests("GET", "thoughts").first?.query["author_id"] == "eq.\(Fixture.userA.uuidString.lowercased())")
        #expect(model.isLoading == false)
    }

    @Test func loadFailureSetsTheErrorMessage() async {
        let server = Fixture.feedServer(thoughts: [1])
        server.on("GET", "thoughts", error: .timedOut)
        let model = makeModel(server)
        await model.loadData()

        #expect(model.errorMessage == SupabaseRequestError.offline.errorDescription)
        #expect(model.isLoading == false)
    }

    @Test func createTrimsTextDropsBlankOptionsAndReloads() async throws {
        let server = Fixture.feedServer(thoughts: [9])
        server.on("POST", "thoughts", status: 201, json: #"[{"id":"\#(Fixture.id(9).uuidString)"}]"#)
        server.on("POST", "options", status: 201, json: "")
        let model = makeModel(server)

        try await model.createThought(message: "  Am I the only one?  ", topic: .viajes, options: [" Yes ", "", "   ", "No"])

        let thought = try #require(server.requests("POST", "thoughts").first?.bodyJSON as? [String: Any])
        #expect(thought["message"] as? String == "Am I the only one?")
        #expect(thought["topic"] as? String == "VIAJES")
        let rows = try #require(server.requests("POST", "options").first?.bodyJSON as? [[String: Any]])
        #expect(rows.map { $0["title"] as? String } == ["Yes", "No"])
        // The list was reloaded afterwards.
        #expect(server.requests("GET", "thoughts").count == 1)
        #expect(model.thoughts.map(\.id) == [Fixture.id(9)])
    }

    @Test func createFailureThrowsAndLeavesTheListAlone() async {
        let server = Fixture.feedServer(thoughts: [1])
        server.on("POST", "thoughts", status: 400, json: #"{"code":"23514","message":"banned"}"#)
        let model = makeModel(server)
        await model.loadData()

        do {
            try await model.createThought(message: "bad", topic: .general, options: ["A", "B"])
            Issue.record("Expected a throw")
        } catch {
            #expect(error as? SupabaseRequestError == .contentRejected)
            #expect(model.thoughts.count == 1)
        }
    }

    @Test func previewCreateAddsLocallyWithoutABackend() async throws {
        let model = MyThoughtsViewModel()
        try await model.createThought(message: "Hi", topic: .general, options: ["A", "B"])
        #expect(model.thoughts.first?.message == "Hi")
        #expect(model.thoughts.first?.options.count == 2)
    }
}
