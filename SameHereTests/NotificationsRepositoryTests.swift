//
//  NotificationsRepositoryTests.swift
//  SameHereTests
//

import Foundation
import Testing
@testable import SameHere

struct NotificationsRepositoryTests {

    @Test func registerCallsTheRPCWithNamedArguments() async throws {
        let server = StubServer()
        server.on("POST", "rpc/register_device_token", status: 204, json: "")
        let repo = NotificationsRepository(client: server.makeClient())

        try await repo.register(token: "abc123", environment: .sandbox, locale: "es", frequency: .weekly)

        let body = try #require(server.requests("POST", "rpc/register_device_token").first?.bodyJSON as? [String: Any])
        #expect(body["p_token"] as? String == "abc123")
        #expect(body["p_environment"] as? String == "sandbox")
        #expect(body["p_locale"] as? String == "es")
        #expect(body["p_frequency"] as? String == "weekly")
    }

    @Test func unregisterDeletesOnlyThisToken() async throws {
        let server = StubServer()
        server.on("DELETE", "device_tokens", status: 204, json: "")

        try await NotificationsRepository(client: server.makeClient()).unregister(token: "abc123")

        let request = try #require(server.requests("DELETE", "device_tokens").first)
        #expect(request.query["token"] == "eq.abc123")
    }
}
