import XCTest
@testable import AssistantModels

/// The xAI / Grok device-code sign-in (Play XaiAuth and DeviceCode), against fake issuers only:
/// every host is a `.invalid` one on the intercept-all fixture.
final class XAISignInTests: XCTestCase {
    /// A clock the fake sleeps move forward, recording each wait in milliseconds.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var now: Int64 = 1_800_000_000_000
        private(set) var sleeps: [Int64] = []
        var value: Int64 { lock.lock(); defer { lock.unlock() }; return now }
        func sleep(_ ms: Int64) { lock.lock(); sleeps.append(ms); now += ms; lock.unlock() }
    }

    final class Polls: @unchecked Sendable {
        private let lock = NSLock()
        private var queued: [XAIDevicePoll]
        private(set) var codes: [String] = []
        init(_ polls: [XAIDevicePoll]) { queued = polls }
        func next(_ code: String) -> XAIDevicePoll {
            lock.lock(); defer { lock.unlock() }
            codes.append(code)
            return queued.isEmpty ? .pending : queued.removeFirst()
        }
    }

    private func grant(expiresIn: Int64 = 900, interval: Int64 = 5) -> XAIDeviceGrant {
        XAIDeviceGrant(challenge: XAIDeviceChallenge(userCode: "ABCD-1234", verificationURI: "https://accounts.x.ai/oauth2/device",
                                                     verificationURIComplete: nil, expiresIn: expiresIn, interval: interval),
                       deviceCode: "device-code-not-shown")
    }

    private func wait(_ polls: [XAIDevicePoll], grant: XAIDeviceGrant? = nil) async -> (Result<XAITokens, Error>, Clock, Polls) {
        let clock = Clock()
        let queue = Polls(polls)
        do {
            let tokens = try await XAIAuthClient.awaitGrant(grant ?? self.grant(), nowMs: { clock.value },
                                                            sleep: { clock.sleep($0) }, poll: { queue.next($0) })
            return (.success(tokens), clock, queue)
        } catch {
            return (.failure(error), clock, queue)
        }
    }

    private static let tokens = XAITokens(accessToken: "at", refreshToken: "rt", expiresIn: 3600, scopes: ["api:access"])

    func testPollingWaitsTheServersIntervalAndSlowsDownByFiveSeconds() async throws {
        let (result, clock, polls) = await wait([.pending, .slowDown, .pending, .tokens(Self.tokens)])
        XCTAssertEqual(try result.get(), Self.tokens)
        XCTAssertEqual(clock.sleeps, [5_000, 10_000, 10_000], "slow_down adds five seconds for good")
        XCTAssertEqual(polls.codes, Array(repeating: "device-code-not-shown", count: 4), "the device code only goes to the poll")
    }

    func testRefusalsExpiryAndTimeoutEndTheWait() async {
        func reason(_ result: Result<XAITokens, Error>) -> XAISignInFailure? {
            if case .failure(let error) = result { return (error as? XAISignInError)?.reason }
            return nil
        }
        let denied = await wait([.pending, .rejected(code: "access_denied", terminal: true)]).0
        XCTAssertEqual(reason(denied), .denied)
        let expired = await wait([.rejected(code: "expired_token", terminal: true)]).0
        XCTAssertEqual(reason(expired), .expired)
        let other = await wait([.rejected(code: "invalid_client", terminal: true)]).0
        XCTAssertEqual(reason(other), .rejected)
        if case .failure(let error) = other { XCTAssertEqual((error as? XAISignInError)?.code, "invalid_client") }
        let (timedOut, clock, _) = await wait([], grant: grant(expiresIn: 20, interval: 5))
        XCTAssertEqual(reason(timedOut), .timedOut)
        XCTAssertEqual(clock.sleeps.reduce(0, +), 20_000, "never waits past the code's lifetime")
    }

    func testOnlyThreeFailedPollsInARowEndTheWait() async throws {
        let (recovered, _, _) = await wait([.failed(.network("x")), .failed(.server(502)), .pending, .failed(.network("x")),
                                            .failed(.network("x")), .tokens(Self.tokens)])
        XCTAssertEqual(try recovered.get(), Self.tokens, "a moment without the network while the person is on xAI's page")
        let (failed, _, polls) = await wait([.failed(.network("x")), .failed(.network("x")), .failed(.network("x")), .tokens(Self.tokens)])
        if case .failure(let error) = failed { XCTAssertEqual((error as? XAISignInError)?.reason, .network) } else { XCTFail("three failures end it") }
        XCTAssertEqual(polls.codes.count, 3)
    }

    func testPollAnswersAreReadLikeRFC8628() {
        func poll(_ status: Int, _ body: String) -> XAIDevicePoll { XAIAuthClient.interpret(status: status, body: Data(body.utf8)) }
        XCTAssertEqual(poll(400, #"{"error":"authorization_pending"}"#), .pending)
        XCTAssertEqual(poll(400, #"{"error":"slow_down"}"#), .slowDown)
        XCTAssertEqual(poll(429, "busy"), .slowDown)
        XCTAssertEqual(poll(400, #"{"error":"access_denied"}"#), .rejected(code: "access_denied", terminal: true))
        XCTAssertEqual(poll(503, ""), .failed(.server(503)))
        XCTAssertEqual(poll(200, #"{"token_type":"Bearer"}"#), .rejected(code: "no_access_token", terminal: true))
        XCTAssertEqual(poll(200, #"{"access_token":"at","refresh_token":"rt","expires_in":"1800","scope":"openid api:access"}"#),
                       .tokens(XAITokens(accessToken: "at", refreshToken: "rt", expiresIn: 1800, scopes: ["openid", "api:access"])))
    }

    func testOnlyHTTPSOnTheAllowedHostsIsUsed() {
        XCTAssertNotNil(OAuthHosts.allowed("https://auth.x.ai/oauth2/token", hosts: XAISignIn.issuerHosts))
        XCTAssertNil(OAuthHosts.allowed("http://auth.x.ai/oauth2/token", hosts: XAISignIn.issuerHosts), "never plain HTTP")
        XCTAssertNil(OAuthHosts.allowed("https://auth.x.ai.evil.invalid/x", hosts: XAISignIn.issuerHosts))
        XCTAssertNil(OAuthHosts.allowed("https://user@auth.x.ai/x", hosts: XAISignIn.issuerHosts), "no user info")
        XCTAssertNil(OAuthHosts.allowed("https://accounts.x.ai/oauth2/device", hosts: XAISignIn.issuerHosts),
                     "the verification host is not a token host")
        XCTAssertNotNil(OAuthHosts.allowed("https://accounts.x.ai/oauth2/device", hosts: XAISignIn.verifyHosts))
        XCTAssertNotNil(OAuthHosts.allowed("http://127.0.0.1:8080/x", hosts: ["127.0.0.1"]), "loopback test servers only")
    }

    private func discovery(_ host: String, device: String? = nil, token: String? = nil, issuer: String? = nil) -> String {
        let base = "https://" + host
        return """
        {"issuer":"\(issuer ?? base)","device_authorization_endpoint":"\(device ?? base + "/oauth2/device/code")",\
        "token_endpoint":"\(token ?? base + "/oauth2/token")","userinfo_endpoint":"\(base)/oauth2/userinfo"}
        """
    }

    private func client(_ server: AccountProtocolFixture.Server, verify: Set<String> = ["accounts.x.ai"]) -> XAIAuthClient {
        XAIAuthClient(http: AccountProtocolFixture.http(), issuer: server.base.absoluteString, clientID: XAISignIn.clientID,
                      issuerHosts: [server.host], verifyHosts: verify.union([server.host]))
    }

    func testDiscoveryRefusesAnotherIssuerOrHostBeforeSendingAnything() async throws {
        let foreign = AccountProtocolFixture.register()
        foreign.enqueue([.json(200, discovery(foreign.host, device: "https://elsewhere.invalid/device"))])
        do {
            _ = try await client(foreign).discover()
            XCTFail("a device endpoint on another host is refused")
        } catch {
            XCTAssertEqual((error as? XAISignInError)?.reason, .badIssuer)
        }
        let impostor = AccountProtocolFixture.register()
        impostor.enqueue([.json(200, discovery(impostor.host, issuer: "https://other.invalid"))])
        do {
            _ = try await client(impostor).discover()
            XCTFail("another issuer is refused")
        } catch {
            XCTAssertEqual((error as? XAISignInError)?.code, "issuer")
        }
        XCTAssertEqual(foreign.requests.map(\.url.path), ["/.well-known/openid-configuration"])
    }

    func testAWholeSignInChecksTheCodeHostsAndScopes() async throws {
        let server = AccountProtocolFixture.register()
        server.enqueue([
            .json(200, discovery(server.host)),
            .json(200, #"{"device_code":"dc-1","user_code":"WXYZ-0001","verification_uri":"https://phishing.invalid/device","verification_uri_complete":"https://phishing.invalid/device?code=WXYZ-0001","expires_in":600,"interval":1}"#),
            .json(400, #"{"error":"authorization_pending"}"#),
            .json(200, #"{"access_token":"at","refresh_token":"rt","expires_in":3600,"scope":"openid email api:access","id_token":"x.eyJzdWIiOiJ1c2VyLTEiLCJlbWFpbCI6ImFAYi5pbnZhbGlkIn0.y"}"#),
            .json(200, #"{"sub":"user-1","email":"a@b.invalid"}"#),
        ])
        let shown = Box<XAIDeviceChallenge?>(nil)
        let clock = Clock()
        let session = try await client(server).signIn(onChallenge: { shown.value = $0 }, sleep: { clock.sleep($0) }, nowMs: { clock.value })
        let challenge = try XCTUnwrap(shown.value)
        XCTAssertEqual(challenge.userCode, "WXYZ-0001")
        XCTAssertEqual(challenge.verificationURI, XAISignIn.fallbackVerify, "a verification page on another host is replaced by xAI's own")
        XCTAssertNil(challenge.verificationURIComplete, "and the one with the code in it is dropped")
        XCTAssertEqual(session.accessToken, "at")
        XCTAssertEqual(session.refreshToken, "rt")
        XCTAssertEqual(session.label, "a@b.invalid")
        XCTAssertEqual(session.accountId, "user-1")
        XCTAssertEqual(session.tokenURL, server.base.absoluteString + "/oauth2/token")
        XCTAssertEqual(session.apiBase, "https://api.x.ai/v1")
        let requests = server.requests
        XCTAssertEqual(requests[1].form["client_id"], XAISignIn.clientID)
        XCTAssertEqual(requests[1].form["scope"], XAISignIn.scopes)
        XCTAssertEqual(requests[2].form["grant_type"], XAISignIn.deviceGrant)
        XCTAssertEqual(requests[2].form["device_code"], "dc-1")
        XCTAssertEqual(requests[4].header("Authorization"), "Bearer at")

        let planless = AccountProtocolFixture.register()
        planless.enqueue([
            .json(200, discovery(planless.host)),
            .json(200, #"{"device_code":"dc","user_code":"U","verification_uri":"https://accounts.x.ai/oauth2/device","interval":1}"#),
            .json(200, #"{"access_token":"at","scope":"openid email"}"#),
        ])
        do {
            _ = try await client(planless).signIn(onChallenge: { _ in }, sleep: { clock.sleep($0) }, nowMs: { clock.value })
            XCTFail("no subscription scope")
        } catch {
            XCTAssertEqual((error as? XAISignInError)?.reason, .noSubscription)
        }
    }

    func testRefreshUsesTheTokenAddressFromSignInAndSaysWhenItIsDead() async throws {
        let server = AccountProtocolFixture.register()
        let auth = client(server)
        let session = XAISession(accountId: "u", label: "a@b.invalid", accessToken: "at", refreshToken: "rt", expiresAtMs: 0,
                                 scopes: ["api:access"], apiBase: "https://api.x.ai/v1", clientId: XAISignIn.clientID,
                                 issuer: server.base.absoluteString, tokenURL: server.base.absoluteString + "/oauth2/token")
        server.enqueue([.json(200, #"{"access_token":"at2","refresh_token":"rt2","expires_in":1200}"#)])
        guard case .refreshed(let next) = try await auth.refresh(session, nowMs: { 1_000 }) else { return XCTFail("refreshed") }
        XCTAssertEqual(next.accessToken, "at2")
        XCTAssertEqual(next.refreshToken, "rt2")
        XCTAssertEqual(next.expiresAtMs, 1_000 + 1_200_000)
        XCTAssertEqual(next.scopes, ["api:access"], "a refresh without scopes keeps them")
        XCTAssertEqual(server.requests.last?.form["refresh_token"], "rt")
        server.enqueue([.json(400, #"{"error":"invalid_grant"}"#)])
        guard case .rejected(terminal: true) = try await auth.refresh(session) else { return XCTFail("dead refresh token") }
        server.enqueue([.json(500, "")])
        guard case .failed = try await auth.refresh(session) else { return XCTFail("a server failure keeps the sign-in") }
        let count = server.requests.count
        var moved = session
        moved.tokenURL = "https://elsewhere.invalid/token"
        guard case .rejected(terminal: true) = try await auth.refresh(moved) else { return XCTFail("another host is refused") }
        XCTAssertEqual(server.requests.count, count, "and gets nothing")
        var empty = session
        empty.refreshToken = ""
        guard case .rejected(terminal: true) = try await auth.refresh(empty) else { return XCTFail("no refresh token") }
    }
}

/// A value shared with the fakes' closures.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
