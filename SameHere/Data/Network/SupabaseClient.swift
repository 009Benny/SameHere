//
//  SupabaseClient.swift
//  SameHere
//

import Foundation

/// Errors from a PostgREST call.
nonisolated enum SupabaseRequestError: LocalizedError, Equatable {
    /// The device has no usable connection.
    case offline
    /// The session was rejected (401/403). The app should restore or sign in again.
    case unauthorized
    /// A row already exists — for Same Here, this is "you already voted on that".
    case duplicate
    /// Row level security refused the write.
    case forbidden
    /// The text contains a word on the banned list (`supabase/moderation.sql`).
    case contentRejected
    /// Anything else the server said.
    case server(status: Int, message: String)
    /// The response did not decode into the expected shape.
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return String(localized: "You appear to be offline. Check your connection and try again.")
        case .unauthorized:
            return String(localized: "Your session expired. Please sign in again.")
        case .duplicate:
            return String(localized: "You already answered this one.")
        case .forbidden:
            return String(localized: "You don't have permission to do that.")
        case .contentRejected:
            return String(localized: "That contains words that aren't allowed in Same Here. Please rephrase it.")
        case .server(_, let message):
            return message
        case .decoding:
            return String(localized: "The server sent something unexpected.")
        }
    }
}

/// A thin PostgREST client for the Same Here tables.
///
/// The one job worth spelling out: **it asks for a fresh access token on every
/// request** instead of holding on to a session. An `AuthSession` is a snapshot —
/// its access token lives about an hour — so a client that captured one at sign-in
/// would work beautifully all through development and start returning 401s to real
/// users an hour in. `tokenProvider` routes back to
/// `SupabaseAuthService.validAccessToken()`, which refreshes when needed and
/// coalesces concurrent callers into a single refresh.
///
/// Guests are ordinary users here: their JWT carries a real `sub`, so every
/// `auth.uid()` check in the schema works unchanged.
nonisolated struct SupabaseClient: Sendable {

    private let baseURL: URL
    private let anonKey: String
    private let tokenProvider: @Sendable () async throws -> String
    private let urlSession: URLSession

    /// - Parameters:
    ///   - projectURL: The Supabase project root.
    ///   - anonKey: The anon / publishable key.
    ///   - tokenProvider: Returns a currently-valid user access token. Wire this
    ///     to `SupabaseAuthService.validAccessToken()`.
    ///   - urlSession: Injectable transport, for tests.
    init(projectURL: URL,
         anonKey: String,
         tokenProvider: @escaping @Sendable () async throws -> String,
         urlSession: URLSession = .shared) {
        self.baseURL = projectURL.appendingPathComponent("rest").appendingPathComponent("v1")
        self.anonKey = anonKey
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
    }

    // MARK: - Verbs

    /// `GET /rest/v1/<table>` decoded into `T`, which comes from the call site's
    /// type annotation: `let rows: [ThoughtDTO] = try await client.get("thoughts")`.
    func get<T: Decodable>(_ table: String,
                           query: [URLQueryItem] = []) async throws -> T {
        let request = try await makeRequest(table, method: "GET", query: query)
        let data = try await send(request)
        return try decode(T.self, from: data)
    }

    /// `POST /rest/v1/<table>`, returning the inserted rows.
    @discardableResult
    func insert<Body: Encodable, T: Decodable>(_ table: String,
                                               body: Body,
                                               returning type: T.Type) async throws -> T {
        var request = try await makeRequest(table, method: "POST")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode(body)
        let data = try await send(request)
        return try decode(T.self, from: data)
    }

    /// `POST /rest/v1/<table>` where the inserted row is not needed back.
    func insert<Body: Encodable>(_ table: String, body: Body) async throws {
        var request = try await makeRequest(table, method: "POST")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode(body)
        _ = try await send(request)
    }

    /// `POST /rest/v1/rpc/<function>` for a Postgres function that takes no
    /// arguments and returns nothing.
    func rpc(_ function: String) async throws {
        var request = try await makeRequest("rpc/\(function)", method: "POST")
        request.httpBody = Data("{}".utf8)
        _ = try await send(request)
    }

    /// `PATCH /rest/v1/<table>?<filters>` — updates the matching rows.
    func update<Body: Encodable>(_ table: String,
                                 query: [URLQueryItem],
                                 body: Body) async throws {
        var request = try await makeRequest(table, method: "PATCH", query: query)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder.supabase.encode(body)
        _ = try await send(request)
    }

    /// `DELETE /rest/v1/<table>?<filters>`. Always pass a filter: PostgREST
    /// refuses an unfiltered delete, and RLS limits it to the caller's rows.
    func delete(_ table: String, query: [URLQueryItem]) async throws {
        var request = try await makeRequest(table, method: "DELETE", query: query)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await send(request)
    }

    // MARK: - Plumbing

    private func makeRequest(_ table: String,
                             method: String,
                             query: [URLQueryItem] = []) async throws -> URLRequest {
        let token = try await tokenProvider()

        var components = URLComponents(
            url: baseURL.appendingPathComponent(table),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query
            // URLComponents leaves "+" alone, but servers read a bare "+" in a
            // query as a space — which breaks timestamps like "...+00:00".
            let encodedQuery = components?.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
            components?.percentEncodedQuery = encodedQuery
        }

        guard let url = components?.url else {
            throw SupabaseRequestError.server(status: 0, message: "Could not build a URL for \(table).")
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed:
                throw SupabaseRequestError.offline
            default:
                throw SupabaseRequestError.server(status: 0, message: error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseRequestError.decoding("Not an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw postgrestError(status: http.statusCode, data: data)
        }
        return data
    }

    /// Maps a PostgREST error body onto something the UI can act on.
    ///
    /// `23505` is the Postgres unique-violation code. `answers` has
    /// `unique (thought_id, user_id)`, so that is the database enforcing
    /// one vote per person per thought — a normal outcome, not a failure.
    private func postgrestError(status: Int, data: Data) -> SupabaseRequestError {
        let payload = try? JSONDecoder().decode(PostgrestError.self, from: data)
        let code = payload?.code ?? ""
        let message = payload?.message ?? "The server returned status \(status)."

        if code == "23505" { return .duplicate }
        if code == "42501" { return .forbidden }
        if code == "23514" { return .contentRejected }

        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 409: return .duplicate
        default: return .server(status: status, message: message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.supabase.decode(T.self, from: data)
        } catch {
            throw SupabaseRequestError.decoding(String(describing: error))
        }
    }

    private struct PostgrestError: Decodable {
        let code: String?
        let message: String?
        let details: String?
        let hint: String?
    }
}

// MARK: - Coding

extension JSONDecoder {
    /// Decoder matching the schema's conventions: snake_case columns and
    /// `timestamptz` values with a variable number of fractional digits.
    nonisolated(unsafe) static let supabase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            return PostgresTimestamp.parse(raw) ?? .distantPast
        }
        return decoder
    }()
}

extension JSONEncoder {
    nonisolated(unsafe) static let supabase: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

/// Postgres renders `timestamptz` with 0–6 fractional digits;
/// `ISO8601DateFormatter` accepts only 0 or 3, so the fraction is normalised
/// before parsing. Without this, `.iso8601` fails on real rows.
nonisolated enum PostgresTimestamp {
    static func parse(_ raw: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }

        guard let dot = raw.firstIndex(of: ".") else { return nil }
        let tail = raw[raw.index(after: dot)...]
        let digits = tail.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let normalized = raw[raw.startIndex..<dot] + "." + digits.prefix(3) + tail.dropFirst(digits.count)
        return fractional.date(from: String(normalized))
    }
}
