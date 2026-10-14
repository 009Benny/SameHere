//
//  SupabaseClientTests.swift
//  SameHereTests
//

import Foundation
import Testing
@testable import SameHere

struct SupabaseClientTests {

    private struct Row: Decodable, Equatable { let thoughtId: UUID }

    /// Runs `body` and returns the `SupabaseRequestError` it threw, if any.
    private func thrownError(_ body: () async throws -> Void) async -> SupabaseRequestError? {
        do { try await body(); return nil } catch { return error as? SupabaseRequestError }
    }

    private func getError(status: Int, json: String) async -> SupabaseRequestError? {
        let server = StubServer()
        server.on("GET", "t", status: status, json: json)
        let client = server.makeClient()
        return await thrownError { let _: [Row] = try await client.get("t") }
    }

    // MARK: - Requests

    @Test func sendsTheKeyAndAFreshBearerTokenOnEveryRequest() async throws {
        let server = StubServer()
        server.on("GET", "t")
        let counter = Counter()
        let client = server.makeClient { "token-\(await counter.next())" }

        let _: [Row] = try await client.get("t")
        let _: [Row] = try await client.get("t")

        let sent = server.requests
        #expect(sent.count == 2)
        #expect(sent[0].headers["apikey"] == "anon-key")
        #expect(sent[0].headers["Authorization"] == "Bearer token-1")
        // The token is asked for again each time, never cached from sign-in.
        #expect(sent[1].headers["Authorization"] == "Bearer token-2")
    }

    @Test func plusSignsInQueriesAreEncodedSoTimestampsSurvive() async throws {
        let server = StubServer()
        server.on("GET", "t")
        let client = server.makeClient()

        let _: [Row] = try await client.get("t", query: [.init(name: "created_at", value: "lt.2026-08-04T10:00:00+00:00")])

        let request = try #require(server.requests.first)
        #expect(request.url.absoluteString.contains("%2B00:00"))
        #expect(!request.url.absoluteString.contains("+00:00"))
        #expect(request.query["created_at"] == "lt.2026-08-04T10:00:00+00:00")
    }

    @Test func insertAsksForTheRowBackWhenReturning() async throws {
        let server = StubServer()
        server.on("POST", "thoughts", status: 201, json: #"[{"id":"\#(Fixture.id(1).uuidString)"}]"#)
        let client = server.makeClient()

        let rows = try await client.insert(
            "thoughts",
            body: ThoughtInsert(authorId: Fixture.userA, message: "m", topic: "GENERAL", isAiGenerated: false),
            returning: [InsertedIDDTO].self
        )

        #expect(rows.first?.id == Fixture.id(1))
        #expect(server.requests.first?.headers["Prefer"] == "return=representation")
    }

    @Test func minimalInsertAndDeleteAskForNothingBack() async throws {
        let server = StubServer()
        server.on("POST", "answers", status: 201, json: "")
        server.on("DELETE", "thoughts", status: 204, json: "")
        let client = server.makeClient()

        try await client.insert("answers", body: AnswerInsert(thoughtId: Fixture.id(1), optionId: Fixture.id(2), userId: Fixture.userA))
        try await client.delete("thoughts", query: [.init(name: "id", value: "eq.x")])

        #expect(server.requests(  "POST", "answers").first?.headers["Prefer"] == "return=minimal")
        #expect(server.requests("DELETE", "thoughts").first?.headers["Prefer"] == "return=minimal")
    }

    @Test func rpcPostsAnEmptyJSONObject() async throws {
        let server = StubServer()
        server.on("POST", "rpc/delete_my_account", status: 204, json: "")
        try await server.makeClient().rpc("delete_my_account")

        let request = try #require(server.requests.first)
        #expect(request.path == "/rest/v1/rpc/delete_my_account")
        #expect(request.body == Data("{}".utf8))
    }

    @Test func updateUsesPatchWithTheFilter() async throws {
        let server = StubServer()
        server.on("PATCH", "profiles", status: 204, json: "")
        try await server.makeClient().update(
            "profiles",
            query: [.init(name: "id", value: "eq.abc")],
            body: TermsAcceptanceDTO(termsAcceptedAt: "2026-08-04T10:00:00Z")
        )

        let request = try #require(server.requests.first)
        #expect(request.query["id"] == "eq.abc")
        let body = request.bodyJSON as? [String: Any]
        #expect(body?["terms_accepted_at"] as? String == "2026-08-04T10:00:00Z")
    }

    // MARK: - Errors

    @Test func decodesRowsWithSnakeCaseKeys() async throws {
        let server = StubServer()
        server.on("GET", "t", json: Fixture.uuidList("thought_id", [Fixture.id(7)]))
        let rows: [Row] = try await server.makeClient().get("t")
        #expect(rows == [Row(thoughtId: Fixture.id(7))])
    }

    @Test func uniqueViolationIsDuplicate() async {
        #expect(await getError(status: 409, json: #"{"code":"23505","message":"dup"}"#) == .duplicate)
    }

    @Test func rlsViolationIsForbidden() async {
        #expect(await getError(status: 403, json: #"{"code":"42501","message":"rls"}"#) == .forbidden)
    }

    @Test func checkViolationIsContentRejected() async {
        #expect(await getError(status: 400, json: #"{"code":"23514","message":"banned"}"#) == .contentRejected)
    }

    @Test func plainStatusCodesMapWhenThereIsNoPostgresCode() async {
        #expect(await getError(status: 401, json: "{}") == .unauthorized)
        #expect(await getError(status: 403, json: "{}") == .forbidden)
        #expect(await getError(status: 409, json: "{}") == .duplicate)
    }

    @Test func otherStatusesKeepTheServerMessage() async {
        let error = await getError(status: 500, json: #"{"message":"boom"}"#)
        #expect(error == .server(status: 500, message: "boom"))
    }

    @Test func unreadableErrorBodyStillProducesAServerError() async {
        let error = await getError(status: 502, json: "<html>bad gateway</html>")
        #expect(error == .server(status: 502, message: "The server returned status 502."))
    }

    @Test func wrongShapeIsADecodingError() async {
        let error = await getError(status: 200, json: #"{"unexpected":true}"#)
        guard case .decoding = error else {
            Issue.record("Expected .decoding, got \(String(describing: error))")
            return
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost])
    func connectivityFailuresAreOffline(code: URLError.Code) async {
        let server = StubServer()
        server.on("GET", "t", error: code)
        let client = server.makeClient()
        let error = await thrownError { let _: [Row] = try await client.get("t") }
        #expect(error == .offline)
    }

    @Test func tokenProviderFailureReachesTheCaller() async {
        struct NoSession: Error {}
        let server = StubServer()
        server.on("GET", "t")
        let client = server.makeClient { throw NoSession() }
        do {
            let _: [Row] = try await client.get("t")
            Issue.record("Expected a throw")
        } catch {
            #expect(error is NoSession)
            // And nothing was sent without credentials.
            #expect(server.requests.isEmpty)
        }
    }

    @Test func everyErrorHasAUserFacingDescription() {
        let errors: [SupabaseRequestError] = [
            .offline, .unauthorized, .duplicate, .forbidden, .contentRejected,
            .server(status: 500, message: "boom"), .decoding("x")
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}

private actor Counter {
    private var value = 0
    func next() -> Int { value += 1; return value }
}
