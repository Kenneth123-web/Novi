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

        /// Debug simulator → loopback. Devices and Release builds accept only
        /// HTTPS URLs from Info.plist or `-apiBaseURL`.
        var candidates: [URL] = []

        static var `default`: Config {
            if let raw = UserDefaults.standard.string(forKey: "apiBaseURL"),
               let url = URL(string: raw), NetworkURLPolicy.api(url) {
                return Config(baseURL: url, candidates: [url])
            }
            var urls: [URL] = []
            #if DEBUG && targetEnvironment(simulator)
            urls.append(URL(string: "http://127.0.0.1:8000/v1")!)
            #else
            for key in ["NOVAPIBaseURL", "NOVAPIUsbURL", "NOVAPIHostURL"] {
                if let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = URL(string: trimmed), !trimmed.isEmpty,
                       NetworkURLPolicy.api(url) {
                        urls.append(url)
                    }
                }
            }
            #endif
            if urls.isEmpty {
                #if DEBUG && targetEnvironment(simulator)
                urls.append(URL(string: "http://127.0.0.1:8000/v1")!)
                #else
                // Fail closed. A Release build without an HTTPS endpoint must
                // not silently downgrade credentials to a LAN HTTP server.
                urls.append(URL(string: "https://localhost/v1")!)
                #endif
            }
            var unique: [URL] = []
            for url in urls where !unique.contains(url) { unique.append(url) }
            return Config(baseURL: unique[0], candidates: unique)
        }
    }

    private var baseURL: URL
    private let longTimeout: TimeInterval
    private let candidates: [URL]
    private var resolved = false
    private let session: URLSession
    private let tokens: TokenStore
    private var refreshTask: Task<TokenStore.Stored, Error>?
    private var onAuthenticationLost: (@Sendable () -> Void)?

    init(config: Config = .default, tokens: TokenStore = TokenStore()) {
        let safe = config.candidates.filter(NetworkURLPolicy.api)
        #if DEBUG && targetEnvironment(simulator)
        let fallback = URL(string: "http://127.0.0.1:8000/v1")!
        #else
        let fallback = URL(string: "https://localhost/v1")!
        #endif
        self.baseURL = NetworkURLPolicy.api(config.baseURL) ? config.baseURL : fallback
        self.longTimeout = config.timeout
        self.candidates = safe.isEmpty ? [self.baseURL] : safe
        self.tokens = tokens
        let cfg = URLSessionConfiguration.ephemeral
        // Ceiling for Ask/quiz. Auth and the rest set a much shorter
        // timeout on the request itself — 150s of spinner on skip-login
        // is how "can't reach the server" presented on a device.
        cfg.timeoutIntervalForRequest = config.timeout
        cfg.timeoutIntervalForResource = config.timeout
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    /// Hits `/health` so iOS shows the local-network prompt on the sign-in
    /// screen, and so a device build can pick Wi-Fi vs USB vs Bonjour.
    func prepareNetwork() async {
        await resolveBaseURL()
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
        await resolveBaseURL()
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
        await resolveBaseURL()
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

        let task = Task<TokenStore.Stored, Error> { [baseURL, session] in
            var request = URLRequest(url: baseURL.appendingPathComponent("auth/refresh"))
            request.httpMethod = "POST"
            request.timeoutInterval = 12
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
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.timeoutInterval = isLongRunning(path) ? longTimeout : 12
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
            throw APIError.transport(error, reaching: request.url)
        }
    }

    private func isLongRunning(_ path: String) -> Bool {
        path == "ask" || path == "quiz" || path.hasPrefix("quiz/")
            || path.hasSuffix("/summarize") || path.hasSuffix("/translate")
    }

    private func resolveBaseURL() async {
        if resolved { return }
        for url in candidates {
            if await ping(url) {
                baseURL = url
                resolved = true
                return
            }
        }
    }

    private func ping(_ base: URL) async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2
        cfg.timeoutIntervalForResource = 2
        cfg.waitsForConnectivity = false
        let probe = URLSession(configuration: cfg)
        defer { probe.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await probe.data(for: request)
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
