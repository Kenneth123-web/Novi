import Foundation

/// The one place the app talks to the network.
///
/// Two things it does that are easy to leave out and painful to retrofit:
///
/// * **Refresh is serialised.** A launch fires several requests at once. If
///   each notices the stale access token independently they all refresh, and
///   because refresh tokens rotate server-side the first one to land
///   invalidates the rest — the user is signed out on launch. All callers
///   share one in-flight `Task` instead.
/// * **A 401 is retried exactly once.** Twice loops against a server that
///   answers 401 for a reason refreshing cannot fix.
actor APIClient {
    struct Config {
        var baseURL: URL
        // Longer than the server's AI timeout, so the server's structured
        // error arrives instead of this client giving up first and reporting a
        // generic "can't reach the server" for what is really a model outage.
        var timeout: TimeInterval = 150

        /// The simulator shares the host's loopback, so a locally-run API is
        /// reachable at 127.0.0.1 with no configuration. A device build needs
        /// the host's LAN address — pass `-apiBaseURL`.
        static var `default`: Config {
            if let raw = UserDefaults.standard.string(forKey: "apiBaseURL"),
               let url = URL(string: raw) {
                return Config(baseURL: url)
            }
            return Config(baseURL: URL(string: "http://127.0.0.1:8000/v1")!)
        }
    }

    private let config: Config
    private let session: URLSession
    private let tokens: TokenStore
    private var refreshTask: Task<TokenStore.Stored, Error>?
    private var onAuthenticationLost: (@Sendable () -> Void)?

    init(config: Config = .default, tokens: TokenStore = TokenStore()) {
        self.config = config
        self.tokens = tokens
        let cfg = URLSessionConfiguration.ephemeral
        // Generous: an AI call is a model round trip, not a database read.
        cfg.timeoutIntervalForRequest = config.timeout
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    func setAuthenticationLostHandler(_ handler: @escaping @Sendable () -> Void) {
        onAuthenticationLost = handler
    }

    enum Method: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    /// Unauthenticated: register, login, refresh.
    func send<Response: Decodable>(
        _ method: Method,
        _ path: String,
        body: (any Encodable)? = nil,
        query: [String: String] = [:],
        as: Response.Type = Response.self
    ) async throws -> Response {
        let request = try makeRequest(method, path, body: body, query: query, token: nil)
        let (data, status) = try await perform(request)
        guard (200..<300).contains(status) else {
            throw APIError.decode(from: data, status: status)
        }
        return try decode(data)
    }

    /// Authenticated. Refreshes first if the access token is stale, and once
    /// more if the server disagrees with us about that.
    func authed<Response: Decodable>(
        _ method: Method,
        _ path: String,
        body: (any Encodable)? = nil,
        query: [String: String] = [:],
        as: Response.Type = Response.self
    ) async throws -> Response {
        var stored = try await validTokensAsync()
        var request = try makeRequest(method, path, body: body, query: query,
                                      token: stored.accessToken)
        var (data, status) = try await perform(request)

        if status == 401 {
            stored = try await refreshTokens(force: true)
            request = try makeRequest(method, path, body: body, query: query,
                                      token: stored.accessToken)
            (data, status) = try await perform(request)
        }

        guard (200..<300).contains(status) else {
            let error = APIError.decode(from: data, status: status)
            if error.isAuthFailure { signOutLocally() }
            throw error
        }
        return try decode(data)
    }

    // MARK: Tokens

    /// Returns false if the credential could not be persisted, which means the
    /// session will not survive a relaunch.
    @discardableResult
    func store(_ pair: TokenPairDTO) -> Bool {
        tokens.save(
            TokenStore.Stored(
                accessToken: pair.accessToken,
                refreshToken: pair.refreshToken,
                accessExpiresAt: Date().addingTimeInterval(TimeInterval(pair.expiresIn))
            )
        )
    }

    func currentRefreshToken() -> String? { tokens.load()?.refreshToken }
    func hasSession() -> Bool { tokens.load() != nil }

    func signOutLocally() {
        tokens.clear()
        refreshTask = nil
        onAuthenticationLost?()
    }

    /// The stored pair, without refreshing. Split from `validTokensAsync` so
    /// the refresh task can read the current token without recursing into the
    /// refresh it is itself performing.
    private func validTokens() throws -> TokenStore.Stored {
        guard let stored = tokens.load() else {
            throw APIError(code: "NOT_SIGNED_IN", message: "Please sign in.", status: 401,
                           requestID: nil, fieldErrors: [:], reason: nil)
        }
        return stored
    }

    private func validTokensAsync() async throws -> TokenStore.Stored {
        let stored = try validTokens()
        if stored.isAccessValid { return stored }
        return try await refreshTokens(force: false)
    }

    private func refreshTokens(force: Bool) async throws -> TokenStore.Stored {
        // Join the refresh already in flight rather than starting a second.
        if let existing = refreshTask { return try await existing.value }

        let stored = try validTokens()
        if !force, stored.isAccessValid { return stored }

        let task = Task<TokenStore.Stored, Error> { [config, session] in
            var request = URLRequest(url: config.baseURL.appendingPathComponent("auth/refresh"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refresh_token": stored.refreshToken])
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw APIError.decode(from: data, status: status)
            }
            let pair = try JSONDecoder.novi.decode(TokenPairDTO.self, from: data)
            return TokenStore.Stored(
                accessToken: pair.accessToken,
                refreshToken: pair.refreshToken,
                accessExpiresAt: Date().addingTimeInterval(TimeInterval(pair.expiresIn))
            )
        }
        refreshTask = task

        do {
            let fresh = try await task.value
            refreshTask = nil
            tokens.save(fresh)
            return fresh
        } catch {
            refreshTask = nil
            // The refresh token itself is dead; nothing left to try.
            if let api = error as? APIError, api.isAuthFailure { signOutLocally() }
            throw error
        }
    }

    // MARK: Plumbing

    private func makeRequest(
        _ method: Method,
        _ path: String,
        body: (any Encodable)?,
        query: [String: String],
        token: String?
    ) throws -> URLRequest {
        var components = URLComponents(
            url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.novi.encode(AnyEncodable(body))
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw APIError.transport(error)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T { return empty }
        do {
            return try JSONDecoder.novi.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

/// For endpoints whose body the app does not read.
struct EmptyResponse: Decodable { init() {} }

/// `JSONEncoder` cannot encode an `any Encodable` directly; this forwards to
/// the concrete type's own encoder.
private struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encodeTo = { try wrapped.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeTo(encoder) }
}

extension JSONEncoder {
    /// The API is snake_case throughout; converting here keeps every DTO free
    /// of hand-written CodingKeys.
    static let novi: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}

extension JSONDecoder {
    static let novi: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            // Postgres timestamps carry microseconds; ISO8601DateFormatter
            // parses at most milliseconds, so both are tried rather than
            // failing a whole response on a six-digit fraction.
            if let date = ISO8601DateFormatter.withFraction.date(from: raw) { return date }
            if let date = ISO8601DateFormatter.plain.date(from: raw) { return date }
            // A plain date, as the history endpoint returns.
            if let date = DateFormatter.isoDay.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "unrecognised date: \(raw)"
            )
        }
        return d
    }()
}

extension ISO8601DateFormatter {
    static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

extension DateFormatter {
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
