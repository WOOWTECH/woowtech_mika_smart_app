import Foundation

/// The account sign-ins a provider can use instead of an API key, as on the
/// Android direct-download edition (ProviderConfig.Kind.ChatGpt and Xai). Both
/// call the provider's own Responses interface with the account's access token.
public enum ModelAccountKind: String, Codable, Sendable, CaseIterable {
    case chatGPT
    case xai

    /// The provider kind a sign-in saves.
    public var providerKind: ModelProviderKind {
        switch self {
        case .chatGPT: return .chatGPTAccount
        case .xai: return .xaiAccount
        }
    }

    /// Where the model list and Responses live; tokens are only ever sent here.
    public var apiBase: URL {
        switch self {
        case .chatGPT: return ChatGPTSignIn.apiBase
        case .xai: return XAISignIn.apiBase
        }
    }

    /// The provider's name: brand names that stay the same in every language
    /// (Android CHATGPT_NAME and XAI_NAME). The xAI sign-in is another
    /// provider than the xAI API-key preset.
    public var providerName: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .xai: return "xAI / Grok"
        }
    }

    /// How failures name the sign-in (Android XAI_ACCOUNT).
    public var accountName: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .xai: return "xAI"
        }
    }
}

/// Which signed-in account a request uses. The App sets it on an account
/// provider's ModelConfiguration; ModelProviderClient then calls Responses with
/// that account's token instead of chat/completions with an API key.
public struct ModelAccountRoute: Hashable, Sendable {
    public let kind: ModelAccountKind
    public let providerID: UUID

    public init(kind: ModelAccountKind, providerID: UUID) {
        self.kind = kind; self.providerID = providerID
    }
}

/// How an account call ends when the account itself is the reason (the Play
/// ModelError cases ResponsesModel, ChatGptTokens and AccountTokens raise).
/// Like HTTPChatModelError it carries no response body, token or address.
public enum ModelAccountError: Error, LocalizedError, Sendable, Equatable {
    /// The sign-in is gone on this device (signed out, or the refresh token can
    /// no longer be used): sign in again. The provider and its models stay.
    case signInExpired(ModelAccountKind)
    /// The server refused the account's token or its refresh for another
    /// reason; the sign-in is kept (Play ModelError.Auth).
    case unauthorized(ModelAccountKind)
    /// ChatGPT: this account may not use its plan in other apps (HTTP 403,
    /// not eligible, or the plan scope was taken away). Not retried.
    case planNotEligible
    /// ChatGPT: the plan's usage limit was reached. Not retried.
    case planLimitReached
    /// xAI: HTTP 403 means the subscription tier cannot use this interface.
    /// Not retried; an xAI API key works instead.
    case planNotAllowed(ModelAccountKind)
    /// The model refused or filtered the reply and gave no text.
    case contentRefused
    /// The conversation is longer than the model's context.
    case contextTooLong

    public var errorDescription: String? {
        switch self {
        case .signInExpired(let kind): return "The \(kind.accountName) sign-in has expired; sign in again."
        case .unauthorized(let kind): return "The \(kind.accountName) sign-in was refused; sign in again."
        case .planNotEligible: return "This account can't use its ChatGPT plan in other apps."
        case .planLimitReached: return "The ChatGPT usage limit has been reached."
        case .planNotAllowed(let kind): return "Your \(kind.accountName) plan can't use this API; use an API key instead."
        case .contentRefused: return "The model refused to handle this content."
        case .contextTooLong: return "The conversation is longer than the model's context."
        }
    }
}

/// Gives an account's access token (Play BearerToken). `rejected` is a token a
/// server just refused with HTTP 401: the provider then refreshes, unless the
/// saved token is already another one (a concurrent caller refreshed first).
public protocol ModelAccountTokenProviding: Sendable {
    func accessToken(for route: ModelAccountRoute, rejected: String?) async throws -> String
}

/// A saved sign-in the token gate can refresh (ChatGPTSession, XAISession).
public protocol ModelAccountSessionValue: Sendable, Equatable {
    var accessToken: String { get }
    var refreshToken: String { get }
    /// Milliseconds since 1970; 0 when unknown.
    var expiresAtMs: Int64 { get }
    var signedIn: Bool { get }
    /// The tokens cleared; who signed in and the registration stay.
    func signedOut() -> Self
}

/// What one refresh gave (Play OauthTokenResult and TokenResult).
public enum ModelAccountRefreshResult<Session: Sendable>: Sendable {
    /// The new session, already merged with what the refresh left out.
    case refreshed(Session)
    /// `terminal`: this refresh token can't be used again, so this device signs out.
    case rejected(terminal: Bool)
    /// No usable answer (network, 5xx); the tokens are kept.
    case failed(Error)
}

public enum ModelAccountClock {
    public static func nowMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }
}

/// One account's access token (Play ChatGptTokens and AccountTokens): the saved
/// token while it is good for more than `refreshAheadMs` (five minutes);
/// otherwise, or after the server refused it, a refresh whose rotated pair is
/// saved before it is used. Calls run one at a time, so there is never more
/// than one refresh: a refresh token works once, and two refreshes at the same
/// time would sign each other out. A dead refresh token signs this device out
/// (`save` gets the signed-out session; the provider and its models stay); a
/// network or server failure throws and keeps the tokens. `save` gets the
/// session the refresh started from, so storage can tell whether the user
/// signed out or in again meanwhile and then keep what is stored.
public actor ModelAccountTokenGate<Session: ModelAccountSessionValue> {
    public typealias Refresh = @Sendable (Session) async throws -> ModelAccountRefreshResult<Session>

    /// What a call throws when this device has to sign in again, and when the
    /// issuer refused a refresh for another reason.
    private let signInExpired: any Error & Sendable
    private let refused: any Error & Sendable
    private let load: @Sendable () throws -> Session?
    private let save: @Sendable (_ before: Session, _ after: Session) throws -> Void
    private let refresh: Refresh
    private let accept: @Sendable (Session) throws -> Void
    private let nowMs: @Sendable () -> Int64
    private let refreshAheadMs: Int64
    /// The last call in line; the next one starts when it has finished.
    private var tail: Task<Void, Never>?

    /// `accept` checks a refreshed session after it is saved (ChatGPT: the
    /// plan scope); throwing fails the call that asked.
    public init(kind: ModelAccountKind, refreshAheadMs: Int64 = 300_000,
                nowMs: @escaping @Sendable () -> Int64 = { ModelAccountClock.nowMs() },
                load: @escaping @Sendable () throws -> Session?,
                save: @escaping @Sendable (_ before: Session, _ after: Session) throws -> Void,
                refresh: @escaping Refresh,
                accept: @escaping @Sendable (Session) throws -> Void = { _ in }) {
        self.init(signInExpired: ModelAccountError.signInExpired(kind), refused: ModelAccountError.unauthorized(kind),
                  refreshAheadMs: refreshAheadMs, nowMs: nowMs, load: load, save: save, refresh: refresh, accept: accept)
    }

    /// A sign-in that is not a model account (an MCP server's OAuth sign-in):
    /// its calls throw `signInExpired` and `refused` instead of ModelAccountError.
    public init(signInExpired: any Error & Sendable, refused: any Error & Sendable, refreshAheadMs: Int64 = 300_000,
                nowMs: @escaping @Sendable () -> Int64 = { ModelAccountClock.nowMs() },
                load: @escaping @Sendable () throws -> Session?,
                save: @escaping @Sendable (_ before: Session, _ after: Session) throws -> Void,
                refresh: @escaping Refresh,
                accept: @escaping @Sendable (Session) throws -> Void = { _ in }) {
        self.signInExpired = signInExpired; self.refused = refused
        self.refreshAheadMs = refreshAheadMs; self.nowMs = nowMs
        self.load = load; self.save = save; self.refresh = refresh; self.accept = accept
    }

    public func accessToken(rejected: String?) async throws -> String {
        let previous = tail
        // Not cancelled with its caller: a refresh that already reached the
        // issuer must still save the rotated pair.
        let turn = Task { () async throws -> String in
            await previous?.value
            return try await self.current(rejected: rejected)
        }
        tail = Task { _ = try? await turn.value }
        return try await turn.value
    }

    private func current(rejected: String?) async throws -> String {
        guard let session = try load(), session.signedIn else { throw signInExpired }
        let token = session.accessToken
        if !token.isEmpty, token != rejected, nowMs() < session.expiresAtMs - refreshAheadMs { return token }
        guard !session.refreshToken.isEmpty else {
            try? save(session, session.signedOut())
            throw signInExpired
        }
        switch try await refresh(session) {
        case .refreshed(let next):
            // A failed write must not fail this call; the next refresh says
            // whether the stored pair still works.
            try? save(session, next)
            try accept(next)
            return next.accessToken
        case .rejected(let terminal):
            if terminal {
                try? save(session, session.signedOut())
                throw signInExpired
            }
            // A client problem and the like: retrying won't help, but the token isn't dead.
            throw refused
        case .failed(let error):
            throw error
        }
    }
}

/// OAuth requests of the sign-ins: one request, its status and whole body.
/// Only cancellation and a missing answer throw. Redirects are refused, so a
/// refresh token or an authorization code never follows one to another host.
public protocol AccountHTTP: Sendable {
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data)
}

public struct URLSessionAccountHTTP: AccountHTTP {
    /// Android's shortHttp: a 30 second read timeout for sign-in and model lists.
    public static let shared = URLSessionAccountHTTP()
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        var request = request
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request, delegate: RejectModelRedirects())
        guard let http = response as? HTTPURLResponse else { throw AccountTransportFailure.badResponse("not HTTP") }
        return (http.statusCode, data)
    }
}

/// A sign-in request that got no usable answer (Play ModelError.Network,
/// Server and BadResponse). Never carries a token, code or body.
public enum AccountTransportFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case network(String)
    case server(Int)
    case badResponse(String)

    public var description: String {
        switch self {
        case .network(let why): return "network: " + why
        case .server(let status): return "server \(status)"
        case .badResponse(let why): return "bad response: " + why
        }
    }

    /// The same failure as the chat path names it.
    public var modelError: HTTPChatModelError {
        switch self {
        case .network: return .transportFailure
        case .server(let status): return .httpStatus(status)
        case .badResponse: return .invalidResponse
        }
    }
}

/// The provider's model list with an account's token (Android
/// ModelCatalog.openAiCompat: `GET {base}/models`, Bearer access token).
public enum AccountModelList {
    public enum Failure: Error, Equatable, Sendable {
        case auth, server(Int), network, unreadable
    }

    /// `headers`: a provider's session header (OpenCode Go). An empty token
    /// sends no Authorization: a custom service saved without a key.
    public static func request(base: URL, accessToken: String, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("models"), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 30)
        request.httpMethod = "GET"
        if !accessToken.isEmpty { request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WoowAssistant/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// The listed models, in the server's order; the plan's own table and a
    /// plain OpenAI-compatible list both read (ChatGPTSignIn.listedModels).
    public static func fetch(base: URL, accessToken: String, headers: [String: String] = [:],
                             http: any AccountHTTP = URLSessionAccountHTTP.shared) async throws -> [ListedModel] {
        let answer: (status: Int, body: Data)
        do { answer = try await http.send(request(base: base, accessToken: accessToken, headers: headers)) }
        catch {
            try Task.checkCancellation()
            throw Failure.network
        }
        switch answer.status {
        case 200: break
        case 401, 403: throw Failure.auth
        default: throw Failure.server(answer.status)
        }
        guard let models = ChatGPTSignIn.listedModels(answer.body) else { throw Failure.unreadable }
        return Array(models.prefix(ModelProvidersDocument.maximumListedModels).compactMap { model in
            ModelProviderAddress.isModelName(model.id)
                ? ListedModel(id: model.id, contextTokens: model.contextTokens.flatMap { $0 > 0 ? $0 : nil }, vision: model.vision,
                              tools: model.tools)
                : nil
        })
    }
}
