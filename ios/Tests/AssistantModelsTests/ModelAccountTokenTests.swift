import XCTest
@testable import AssistantModels

/// Saved sign-ins and their refresh, against fake issuers only.
final class ModelAccountTokenTests: XCTestCase {
    private static let clock: Int64 = 1_800_000_000_000

    /// Storage the gate reads and writes, recording what it saved.
    final class Store<Session: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Session?
        private(set) var saves: [(before: Session, after: Session)] = []
        init(_ session: Session?) { stored = session }
        var value: Session? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
        func save(_ before: Session, _ after: Session) {
            lock.lock(); saves.append((before, after)); stored = after; lock.unlock()
        }
        var saveCount: Int { lock.lock(); defer { lock.unlock() }; return saves.count }
    }

    private func chatGPT(expiresAt: Int64 = clock + 3_600_000, access: String = "at", refresh: String = "rt",
                         scopes: [String] = [ChatGPTSignIn.planScope]) -> ChatGPTSession {
        ChatGPTSession(clientId: "client-1", sub: "user-1", email: "a@b.invalid", accessToken: access, refreshToken: refresh,
                       idToken: "it", expiresAtMs: expiresAt, scopes: scopes)
    }

    private func gate(_ store: Store<ChatGPTSession>, issuer: AccountProtocolFixture.Server) -> ModelAccountTokenGate<ChatGPTSession> {
        let auth = ChatGPTAuthClient(http: AccountProtocolFixture.http(), issuer: issuer.base.absoluteString)
        return ChatGPTSignIn.tokenGate(auth: auth, load: { store.value }, save: { store.save($0, $1) }, nowMs: { Self.clock })
    }

    private static let rotated = #"{"access_token":"at2","refresh_token":"rt2","expires_in":3600,"scope":"chatgpt.tokens.use.direct openid"}"#

    func testAValidTokenIsUsedAndOneAboutToExpireIsRefreshedFiveMinutesAhead() async throws {
        let issuer = AccountProtocolFixture.register([.json(200, Self.rotated)])
        let store = Store<ChatGPTSession>(chatGPT(expiresAt: Self.clock + 301_000))
        let tokens = gate(store, issuer: issuer)
        let first = try await tokens.accessToken(rejected: nil)
        XCTAssertEqual(first, "at")
        XCTAssertTrue(issuer.requests.isEmpty, "more than five minutes left: no refresh")
        store.value = chatGPT(expiresAt: Self.clock + 299_000)
        let second = try await tokens.accessToken(rejected: nil)
        XCTAssertEqual(second, "at2")
        let form = try XCTUnwrap(issuer.requests.first?.form)
        XCTAssertEqual(form["grant_type"], "refresh_token")
        XCTAssertEqual(form["refresh_token"], "rt")
        XCTAssertEqual(form["client_id"], "client-1")
        XCTAssertEqual(issuer.requests.first?.url.path, "/api/accounts/oauth/token")
        XCTAssertEqual(store.value?.refreshToken, "rt2", "the rotated pair is saved")
        XCTAssertEqual(store.value?.expiresAtMs, Self.clock + 3_600_000)
        XCTAssertEqual(store.saves.first?.before.refreshToken, "rt", "the save names what the refresh started from")
    }

    func testARefusedTokenIsRefreshedUnlessAnotherCallerAlreadyDidIt() async throws {
        let issuer = AccountProtocolFixture.register([.json(200, #"{"access_token":"at3","expires_in":3600}"#)])
        let store = Store<ChatGPTSession>(chatGPT())
        let tokens = gate(store, issuer: issuer)
        let fresh = try await tokens.accessToken(rejected: "at")
        XCTAssertEqual(fresh, "at3", "a 401 refreshes even far from expiry")
        XCTAssertEqual(store.value?.refreshToken, "rt", "an answer without a refresh token keeps the old one")
        let again = try await tokens.accessToken(rejected: "at")
        XCTAssertEqual(again, "at3", "the refused token was already replaced: no second refresh")
        XCTAssertEqual(issuer.requests.count, 1)
    }

    func testConcurrentCallersShareOneRefresh() async throws {
        let issuer = AccountProtocolFixture.register([.json(200, Self.rotated)])
        let store = Store<ChatGPTSession>(chatGPT(expiresAt: 0))
        let tokens = gate(store, issuer: issuer)
        async let one = tokens.accessToken(rejected: nil)
        async let two = tokens.accessToken(rejected: nil)
        async let three = tokens.accessToken(rejected: nil)
        let all = try await [one, two, three]
        XCTAssertEqual(all, ["at2", "at2", "at2"])
        XCTAssertEqual(issuer.requests.count, 1, "one refresh at a time: the others use its result")
        XCTAssertEqual(store.saveCount, 1)
    }

    func testDeadRefreshTokensSignOutAndOtherFailuresKeepTheSignIn() async throws {
        let issuer = AccountProtocolFixture.register()
        let store = Store<ChatGPTSession>(chatGPT(expiresAt: 0))
        let tokens = gate(store, issuer: issuer)
        func failure() async -> Error? {
            do { _ = try await tokens.accessToken(rejected: nil); return nil } catch { return error }
        }
        issuer.enqueue([.json(503, "")])
        let server = await failure()
        XCTAssertEqual(server as? HTTPChatModelError, .httpStatus(503))
        XCTAssertEqual(store.value?.signedIn, true, "a server failure keeps the sign-in")
        issuer.enqueue([.json(401, #"{"error":"invalid_client"}"#)])
        let refused = await failure()
        XCTAssertEqual(refused as? ModelAccountError, .unauthorized(.chatGPT))
        XCTAssertEqual(store.value?.signedIn, true, "a refusal that isn't terminal keeps the sign-in")
        issuer.enqueue([.json(200, #"{"access_token":"at4","expires_in":3600,"scope":"openid"}"#)])
        let planless = await failure()
        XCTAssertEqual(planless as? ModelAccountError, .planNotEligible, "a refresh without the plan scope is not eligible")
        store.value = chatGPT(expiresAt: 0)
        issuer.enqueue([.json(400, #"{"error":"invalid_grant"}"#)])
        let dead = await failure()
        XCTAssertEqual(dead as? ModelAccountError, .signInExpired(.chatGPT))
        XCTAssertEqual(store.value?.signedIn, false)
        XCTAssertEqual(store.value?.clientId, "client-1", "signing out keeps the registration")
        XCTAssertEqual(store.value?.email, "a@b.invalid", "and the identity")
        let count = issuer.requests.count
        let signedOut = await failure()
        XCTAssertEqual(signedOut as? ModelAccountError, .signInExpired(.chatGPT))
        XCTAssertEqual(issuer.requests.count, count, "signed out asks nothing")
        store.value = chatGPT(expiresAt: 0, refresh: "")
        let noRefresh = await failure()
        XCTAssertEqual(noRefresh as? ModelAccountError, .signInExpired(.chatGPT))
        XCTAssertEqual(store.value?.accessToken, "", "an expired token without a refresh token is signed out")
        store.value = nil
        let none = await failure()
        XCTAssertEqual(none as? ModelAccountError, .signInExpired(.chatGPT), "no sign-in on this device")
    }

    func testSessionsRoundTripAndSigningOutKeepsWhoSignedIn() throws {
        let session = chatGPT()
        let decoded = try JSONDecoder().decode(ChatGPTSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded, session)
        XCTAssertTrue(session.planUsage)
        let out = session.signedOut()
        XCTAssertFalse(out.signedIn)
        XCTAssertEqual(out.clientId, "client-1")
        XCTAssertEqual(out.email, "a@b.invalid")
        XCTAssertTrue(out.idToken.isEmpty)
        let xai = XAISession(accountId: "u", label: "a@b.invalid", accessToken: "at", refreshToken: "rt", expiresAtMs: 1,
                             scopes: ["api:access"], apiBase: "https://api.x.ai/v1", clientId: "c", issuer: "https://auth.x.ai",
                             tokenURL: "https://auth.x.ai/oauth2/token")
        XCTAssertEqual(try JSONDecoder().decode(XAISession.self, from: JSONEncoder().encode(xai)), xai)
        let play = try JSONDecoder().decode(XAISession.self, from: Data(#"{"provider":"xai","accountId":"u"}"#.utf8))
        XCTAssertFalse(play.signedIn, "Play's JSON without default fields reads")
        XCTAssertEqual(xai.signedOut().label, "a@b.invalid")
        XCTAssertFalse(xai.signedOut().signedIn)
    }

    func testTheModelListReadsThePlansTableAndAPlainList() async throws {
        let table = #"{"models":[{"slug":"gpt-5.1","display_name":"GPT-5.1","visibility":"list","input_modalities":["text","image"],"context_window":272000},{"slug":"hidden","visibility":"hide"},{"slug":"gpt-5.1-mini","visibility":"list","input_modalities":["text"]}]}"#
        let server = AccountProtocolFixture.register([.json(200, table), .json(200, #"{"data":[{"id":"grok-4"}]}"#), .json(401, "{}")])
        let base = server.base.appendingPathComponent("v1")
        let plan = try await AccountModelList.fetch(base: base, accessToken: "at", http: AccountProtocolFixture.http())
        XCTAssertEqual(plan, [ListedModel(id: "gpt-5.1", contextTokens: 272000, vision: true), ListedModel(id: "gpt-5.1-mini", vision: false)])
        XCTAssertEqual(server.requests.first?.url.path, "/v1/models")
        XCTAssertEqual(server.requests.first?.header("Authorization"), "Bearer at")
        let plain = try await AccountModelList.fetch(base: base, accessToken: "at", http: AccountProtocolFixture.http())
        XCTAssertEqual(plain.map(\.id), ["grok-4"])
        do {
            _ = try await AccountModelList.fetch(base: base, accessToken: "at", http: AccountProtocolFixture.http())
            XCTFail("a refused token fails the list")
        } catch {
            XCTAssertEqual(error as? AccountModelList.Failure, .auth)
        }
    }

    func testProviderKindsAndAccountProvidersAreStoredBackwardCompatibly() throws {
        // A document from before the sign-ins reads unchanged.
        let old = #"{"version":2,"providers":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"OpenRouter","kind":"openAICompatible","baseURL":"https:\/\/openrouter.ai\/api\/v1","credentialAccount":"6F9619FF-8B86-D011-B42D-00C04FC964FF","typedModels":["vendor\/a"]}],"roles":{"main":{"providerID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","model":"vendor\/a"},"vision":{"use":"off"},"light":{"use":"sameAsMain"}}}"#
        let document = try ModelProvidersDocument.decoded(from: Data(old.utf8))
        XCTAssertEqual(document.providers.first?.kind, .openAICompatible)
        XCTAssertNil(document.providers.first?.accountRoute)
        let account = UUID()
        let connected = try document.connectingAccount(.chatGPT, models: [ListedModel(id: "gpt-fixture")], newAccount: account)
        XCTAssertTrue(connected.isNew)
        XCTAssertEqual(connected.provider.kind, .chatGPTAccount)
        XCTAssertEqual(connected.provider.name, "ChatGPT")
        XCTAssertEqual(connected.provider.baseURL, ChatGPTSignIn.apiBase)
        XCTAssertEqual(connected.provider.credentialAccount, account)
        XCTAssertEqual(connected.document.roles, document.roles, "a sign-in chooses no main model by itself")
        let reread = try ModelProvidersDocument.decoded(from: connected.document.encoded())
        XCTAssertEqual(reread, connected.document)
        XCTAssertEqual(reread.accountProvider(.chatGPT)?.accountRoute?.kind, .chatGPT)
        let again = try reread.connectingAccount(.chatGPT, models: nil)
        XCTAssertFalse(again.isNew, "one provider per sign-in kind")
        XCTAssertEqual(again.account, account, "signing in again keeps the item")
        XCTAssertEqual(again.provider.models?.map(\.id), ["gpt-fixture"], "no new list keeps the old one")
        XCTAssertEqual(again.document.defaultModel(of: again.provider.id), "gpt-fixture")
        // An account's tokens only ever go to its own interface.
        var moved = reread
        let index = try XCTUnwrap(moved.providers.firstIndex { $0.kind == .chatGPTAccount })
        moved.providers[index] = ModelProvider(id: moved.providers[index].id, name: "ChatGPT", kind: .chatGPTAccount,
                                               baseURL: URL(string: "https://other.invalid/v1")!, credentialAccount: account)
        XCTAssertThrowsError(try moved.encoded())
        // The API-key form never finds an account provider as "the same provider".
        XCTAssertNil(reread.sameProvider(name: "ChatGPT", baseURL: ChatGPTSignIn.apiBase))
    }
}
