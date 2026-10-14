//
//  StubServer.swift
//  SameHereTests
//
//  A fake PostgREST server. Every test builds its own `StubServer`, which hands
//  out a `URLSession` that never touches the network: requests are answered by
//  the routes registered here, and recorded so tests can check exactly what the
//  app sent. Each server has an id carried in a header, so tests that run in
//  parallel never see each other's traffic.
//

import Foundation
@testable import SameHere

struct RecordedRequest: Sendable {
    let method: String
    let path: String
    let url: URL
    let headers: [String: String]
    let body: Data?

    /// Decoded query items (so "%2B" reads back as "+").
    var query: [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    var bodyJSON: Any? {
        body.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }
}

final class StubServer: @unchecked Sendable {

    struct Response {
        var status: Int = 200
        var body: String = "[]"
        var error: URLError.Code? = nil
    }

    private struct Route {
        let method: String
        let path: String
        let respond: @Sendable (RecordedRequest) -> Response
    }

    private let lock = NSLock()
    private var routes: [Route] = []
    private var log: [RecordedRequest] = []
    fileprivate let id = UUID().uuidString

    static let projectURL = URL(string: "https://example.supabase.co")!
    static let registry = Registry()

    init() { Self.registry.set(self, for: id) }
    deinit { Self.registry.remove(id) }

    // MARK: - Setup

    /// Answers `method /rest/v1/<table>` with a fixed response.
    func on(_ method: String, _ table: String, status: Int = 200, json: String = "[]") {
        on(method, table) { _ in Response(status: status, body: json) }
    }

    func on(_ method: String, _ table: String, error code: URLError.Code) {
        on(method, table) { _ in Response(error: code) }
    }

    func on(_ method: String, _ table: String,
            respond: @escaping @Sendable (RecordedRequest) -> Response) {
        lock.lock(); defer { lock.unlock() }
        routes.removeAll { $0.method == method && $0.path == "/rest/v1/\(table)" }
        routes.append(Route(method: method, path: "/rest/v1/\(table)", respond: respond))
    }

    func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [StubURLProtocol.idHeader: id]
        return URLSession(configuration: config)
    }

    func makeClient(token: @escaping @Sendable () async throws -> String = { "test-token" }) -> SupabaseClient {
        SupabaseClient(projectURL: Self.projectURL,
                       anonKey: "anon-key",
                       tokenProvider: token,
                       urlSession: makeSession())
    }

    // MARK: - Inspection

    var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    func requests(_ method: String, _ table: String) -> [RecordedRequest] {
        requests.filter { $0.method == method && $0.path == "/rest/v1/\(table)" }
    }

    // MARK: - Used by the URLProtocol

    fileprivate func handle(_ request: RecordedRequest) -> Response {
        lock.lock()
        log.append(request)
        let route = routes.first { $0.method == request.method && $0.path == request.path }
        lock.unlock()
        // Unknown routes answer 404 so a missing stub fails loudly, not silently.
        return route?.respond(request) ?? Response(status: 404, body: #"{"message":"no stub for \#(request.method) \#(request.path)"}"#)
    }

    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var servers: [String: StubServer] = [:]
        func set(_ server: StubServer, for id: String) { lock.lock(); servers[id] = server; lock.unlock() }
        func remove(_ id: String) { lock.lock(); servers[id] = nil; lock.unlock() }
        func server(for id: String) -> StubServer? { lock.lock(); defer { lock.unlock() }; return servers[id] }
    }
}

final class StubURLProtocol: URLProtocol {
    static let idHeader = "X-Stub-Server-ID"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url,
              let id = request.value(forHTTPHeaderField: Self.idHeader),
              let server = StubServer.registry.server(for: id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET",
            path: url.path,
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? readBodyStream()
        )
        let response = server.handle(recorded)

        if let code = response.error {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status,
                                   httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLSession turns `httpBody` into a stream before it reaches a protocol.
    private func readBodyStream() -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

// MARK: - Fixtures

enum Fixture {
    static let userA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    static let userB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    /// A `thoughts` row. `author` nil = seeded question.
    static func thoughtJSON(_ n: Int,
                            message: String? = nil,
                            author: UUID? = nil,
                            createdAt: String = "2026-08-04T10:00:00.123456+00:00",
                            link: String? = nil) -> String {
        let authorJSON = author.map { "\"\($0.uuidString.lowercased())\"" } ?? "null"
        let linkJSON = link.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id(n).uuidString.lowercased())","message":"\(message ?? "Question \(n)")","topic":"GENERAL",
         "created_at":"\(createdAt)","author_id":\(authorJSON),"is_ai_generated":\(author == nil),
         "source_link":\(linkJSON),"profiles":null}
        """
    }

    static func thoughtsJSON(_ numbers: [Int]) -> String {
        "[" + numbers.map { thoughtJSON($0) }.joined(separator: ",") + "]"
    }

    /// `option_results` rows: two options per thought, in order.
    static func optionsJSON(for numbers: [Int], votes: (Int, Int) = (3, 1)) -> String {
        let rows = numbers.flatMap { n -> [String] in
            [
                #"{"option_id":"\#(id(n * 10 + 1).uuidString.lowercased())","thought_id":"\#(id(n).uuidString.lowercased())","title":"Yes","position":0,"votes":\#(votes.0)}"#,
                #"{"option_id":"\#(id(n * 10 + 2).uuidString.lowercased())","thought_id":"\#(id(n).uuidString.lowercased())","title":"No","position":1,"votes":\#(votes.1)}"#
            ]
        }
        return "[" + rows.joined(separator: ",") + "]"
    }

    static func uuidList(_ key: String, _ ids: [UUID]) -> String {
        "[" + ids.map { #"{"\#(key)":"\#($0.uuidString.lowercased())"}"# }.joined(separator: ",") + "]"
    }

    /// A server with the three "what to hide" tables empty and the given feed.
    static func feedServer(thoughts: [Int],
                           answered: [UUID] = [], reported: [UUID] = [], blocked: [UUID] = []) -> StubServer {
        let server = StubServer()
        server.on("GET", "my_answers", json: "[" + answered.map {
            #"{"thought_id":"\#($0.uuidString.lowercased())","option_id":"\#(id(999).uuidString.lowercased())"}"#
        }.joined(separator: ",") + "]")
        server.on("GET", "reports", json: uuidList("thought_id", reported))
        server.on("GET", "blocks", json: uuidList("blocked_id", blocked))
        server.on("GET", "thoughts", json: thoughtsJSON(thoughts))
        server.on("GET", "option_results", json: optionsJSON(for: thoughts))
        return server
    }
}
