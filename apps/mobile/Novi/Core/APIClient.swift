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
        // Ceiling for Ask/quiz only. Auth used to inherit this 150s session
        // timer: URLSession ignores URLRequest.timeoutInterval, so Skip sat
        // on a dead API until the AI timeout fired.
        var timeout: TimeInterval = 150
        var shortTimeout: TimeInterval = 12

        /// Simulator → loopback. Device → Wi-Fi, USB and Bonjour URLs from
        /// Info.plist, probed in order. `-apiBaseURL` still wins when a launch
        /// argument is present.
        var candidates: [URL] = []

        static var `default`: Config {
            if let raw = UserDefaults.standard.string(forKey: "apiBaseURL"),
               let url = URL(string: raw) {
                return Config(baseURL: url, candidates: [url])
            }
            var urls: [URL] = []
            #if targetEnvironment(simulator)
            urls.append(URL(string: "http://127.0.0.1:8000/v1")!)
            urls.append(URL(string: "http://localhost:8000/v1")!)
            #else
            for key in ["NOVAPIBaseURL", "NOVAPIUsbURL", "NOVAPIHostURL", "NOVAPITunnelURL"] {
                if let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = URL(string: trimmed), !trimmed.isEmpty {
                        urls.append(url)
                    }
                }
            }
            #endif
            if urls.isEmpty {
                urls.append(URL(string: "http://127.0.0.1:8000/v1")!)
            }
            var unique: [URL] = []
            for url in urls where !unique.contains(url) { unique.append(url) }
            return Config(baseURL: unique[0], candidates: unique)
        }
    }

    private var baseURL: URL
    private let longTimeout: TimeInterval
    private let shortTimeout: TimeInterval
    private let candidates: [URL]
    private var resolved = false
    private let shortSession: URLSession
    private let longSession: URLSession
    private let tokens: TokenStore
    private var refreshTask: Task<TokenStore.Stored, Error>?
    private var onAuthenticationLost: (@Sendable () -> Void)?

    init(config: Config = .default, tokens: TokenStore = TokenStore()) {
        self.baseURL = config.baseURL
        self.longTimeout = config.timeout
        self.shortTimeout = config.shortTimeout
        self.candidates = config.candidates.isEmpty ? [config.baseURL] : config.candidates
        self.tokens = tokens
        // Two sessions. URLSession uses the *configuration* timer, not
        // URLRequest.timeoutInterval, so a single 150s session made every
        // failed Skip wait out the AI ceiling.
        self.shortSession = Self.makeSession(timeout: config.shortTimeout)
        self.longSession = Self.makeSession(timeout: config.timeout)
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    /// Hits `/health` so iOS shows the local-network prompt on the sign-in
    /// screen, and so a device build can pick Wi-Fi vs USB vs Bonjour.
    func prepareNetwork() async {
        _ = try? await resolveBaseURL()
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
        try await resolveBaseURL()
        let request = try makeRequest(method, path, body: body, query: query, token: nil)
        let (data, status) = try await perform(request, path: path)
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
        try await resolveBaseURL()
        var stored = try await validTokensAsync()
        var request = try makeRequest(method, path, body: body, query: query,
                                      token: stored.accessToken)
        var (data, status) = try await perform(request, path: path)

        if status == 401 {
            stored = try await refreshTokens(force: true)
            request = try makeRequest(method, path, body: body, query: query,
                                      token: stored.accessToken)
            (data, status) = try await perform(request, path: path)
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

        // Run off this actor: `send` would re-enter it while we wait on
        // `refreshTask`, and a second authed call would deadlock.
        let session = shortSession
        let url = baseURL.appending(path: "auth/refresh")
        let timeout = shortTimeout
        let refreshToken = stored.refreshToken
        let task = Task<TokenStore.Stored, Error> {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])
            let (data, response) = try await Self.timedData(
                using: session, for: request, timeout: timeout
            )
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
            url: baseURL.appending(path: path), resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.timeoutInterval = isLongRunning(path) ? longTimeout : shortTimeout
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

    private func perform(_ request: URLRequest, path: String) async throws -> (Data, Int) {
        let longRunning = isLongRunning(path)
        let timeout = longRunning ? longTimeout : shortTimeout
        let session = longRunning ? longSession : shortSession
        do {
            let (data, response) = try await Self.timedData(
                using: session, for: request, timeout: timeout
            )
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            if !longRunning { resolved = false }
            throw APIError.transport(error, reaching: request.url, longRunning: longRunning)
        }
    }

    /// URLSession's own timers start after the socket is up. A closed or
    /// black-holed port can sit in SYN-retry well past `timeoutIntervalForRequest`,
    /// which is how Skip as developer showed "took too long to answer".
    nonisolated private static func timedData(
        using session: URLSession, for request: URLRequest, timeout: TimeInterval
    ) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await session.data(for: request) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw URLError(.timedOut)
            }
            guard let first = try await group.next() else {
                throw URLError(.timedOut)
            }
            group.cancelAll()
            return first
        }
    }

    private func isLongRunning(_ path: String) -> Bool {
        path == "ask" || path == "quiz" || path.hasPrefix("quiz/")
            || path.hasSuffix("/summarize") || path.hasSuffix("/translate")
    }

    private func resolveBaseURL() async throws {
        if resolved { return }
        if let url = await firstReachable() {
            baseURL = url
            resolved = true
            return
        }
        throw APIError.transport(
            URLError(.cannotConnectToHost),
            reaching: candidates.first ?? baseURL
        )
    }

    /// Probe every candidate together. Sequential pings used to spend 4s on a
    /// dead LAN IP before even trying USB, Bonjour or the HTTPS tunnel, which
    /// is how a leftover content filter made Skip look like a timeout.
    private func firstReachable() async -> URL? {
        let session = shortSession
        let urls = candidates
        return await withTaskGroup(of: (Int, URL)?.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    await Self.ping(url, session: session) ? (index, url) : nil
                }
            }
            var winner: (Int, URL)?
            for await result in group {
                guard let result else { continue }
                if winner == nil || result.0 < winner!.0 { winner = result }
                if result.0 == 0 {
                    group.cancelAll()
                    return result.1
                }
            }
            return winner?.1
        }
    }

    nonisolated private static func ping(_ base: URL, session: URLSession) async -> Bool {
        var request = URLRequest(url: base.appending(path: "health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await timedData(
                using: session, for: request, timeout: 4
            )
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return obj["status"] as? String == "ok"
        } catch {
            return false
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
