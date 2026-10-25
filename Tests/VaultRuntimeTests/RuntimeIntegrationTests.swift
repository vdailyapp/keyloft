import Foundation
import KeyloftTestSupport
import Testing
import TokenVault
import VaultDomain
import VaultRuntime

@Suite("VaultRuntime tích hợp")
struct RuntimeIntegrationTests {
    /// Dựng runtime thật trên SQLite in-memory + store/stub giả; đăng ký route Google.
    static func makeRuntime(
        tokenJSON: String? = nil
    ) throws -> (VaultRuntime, StubHTTPClient, InMemorySecretStore) {
        let stub = StubHTTPClient()
        let provider = TestData.googleProvider
        let idToken = TestJWT.make(
            claims: TestJWT.claims(
                iss: provider.issuer, sub: "sub-i1", aud: ["test-client-id.apps.googleusercontent.com"]))
        let json =
            tokenJSON
            ?? #"{"access_token":"at-live","token_type":"Bearer","refresh_token":"rt-live","expires_in":3600,"scope":"openid https://www.googleapis.com/auth/userinfo.email drive","id_token":""#
            + idToken + #""}"#
        // Runtime dựng ProviderCatalog với Provider.google THẬT — route theo URL thật.
        stub.on("POST", "https://oauth2.googleapis.com/token", json: json)
        stub.on(
            "GET", "https://www.googleapis.com",
            json: #"{"user": {"emailAddress": "user@example.test"}, "storageQuota": {"usage": "10", "limit": "100"}}"#)
        stub.on("POST", "https://oauth2.googleapis.com/revoke", json: "{}")

        let store = InMemorySecretStore()
        let runtime = VaultRuntime(
            RuntimeDependencies.inMemory(
                http: stub,
                browser: FakeBrowserSession(behavior: .redirect(code: "code-live", state: .echo, iss: nil)),
                clock: FixedDateProvider(),
                ids: SequentialIDGenerator(),
                random: SeededRandomSource(seed: 21),
                store: store))
        return (runtime, stub, store)
    }

    static func seedClient(_ runtime: VaultRuntime) async throws -> OAuthClient {
        let client = TestData.oauthClient(
            provider: .google,
            clientId: "test-client-id.apps.googleusercontent.com",
            hasSecret: false)
        try await runtime.clients.save(client)
        return client
    }

    @Test("I1: login end-to-end — account healthy trong GRDB, secret trong store, token seed")
    func loginEndToEnd() async throws {
        let (runtime, _, store) = try Self.makeRuntime()
        let client = try await Self.seedClient(runtime)

        let outcome = try await runtime.scopes.execute(
            LoginRequest(
                oauthClientId: client.id,
                scopes: ["openid", "email", "drive"],
                target: .newAccount))

        #expect(outcome.account.status == .healthy)
        let persisted = try await runtime.accounts.get(outcome.account.id)
        #expect(persisted?.status == .healthy)
        #expect(persisted?.externalId == "sub-i1")

        let secret = try await runtime.secrets.list(kind: .refreshToken).first
        #expect(secret != nil)
        #expect(await store.storedRefs.contains { $0 == secret?.keychainRef })

        // onCredentialIssued đã seed token vào cache.
        let cached = await runtime.tokens.cachedToken(for: outcome.account.id)
        #expect(cached?.value == "at-live")
    }

    @Test("I2: health check 60 lần → giữ 50 kết quả (GRDB retention thật)")
    func healthRetention() async throws {
        let (runtime, _, _) = try Self.makeRuntime()
        let client = try await Self.seedClient(runtime)
        let outcome = try await runtime.scopes.execute(
            LoginRequest(
                oauthClientId: client.id, scopes: ["openid", "email", "drive"],
                target: .newAccount))

        let clock = FixedDateProvider()
        for _ in 0..<60 {
            _ = try await runtime.health.check(outcome.account.id, actor: .scheduler)
            clock.advance(by: 1)
        }
        let all = try await runtime.healthResults.list(for: outcome.account.id, limit: 100)
        #expect(all.count == 50)
    }

    @Test("I3: vòng đời đầy đủ trên GRDB — login ×2, health, token, removeAccount")
    func fullLifecycle() async throws {
        let (runtime, _, store) = try Self.makeRuntime()
        let client = try await Self.seedClient(runtime)

        let first = try await runtime.scopes.execute(
            LoginRequest(
                oauthClientId: client.id, scopes: ["openid", "email", "drive"],
                target: .newAccount))
        let second = try await runtime.scopes.execute(
            LoginRequest(
                oauthClientId: client.id, scopes: ["openid", "email", "drive"],
                target: .newAccount))
        #expect(first.account.id == second.account.id)

        _ = try await runtime.health.check(second.account.id, actor: .user)
        let token = try await runtime.tokens.accessToken(for: second.account.id)
        #expect(token.value == "at-live")

        let report = try await runtime.scopes.removeAccount(
            second.account.id, acknowledgeGrantWideRevocation: true)
        #expect(report.leftoverSecrets.isEmpty)

        #expect(try await runtime.accounts.get(second.account.id) == nil)
        #expect(try await runtime.credentials.list(for: second.account.id).isEmpty)
        #expect(try await runtime.healthResults.list(for: second.account.id, limit: 10).isEmpty)
        #expect(await store.storedRefs.isEmpty)

        let actions = try await runtime.audit.query(AuditQuery(limit: 100))
        let sequence = actions.map(\.action)
        for expected in [
            AuditAction.credentialIssued, .accountAdded, .credentialSuperseded,
            .accountStatusChanged, .accountRemoved,
        ] {
            #expect(sequence.contains(expected), "thiếu \(expected) trong audit")
        }
        // Mới nhất trước: account.removed nằm đầu.
        #expect(sequence.first == .accountRemoved)
    }

    @Test("U13: KEYLOFT_DEV_LOGIN_KEYCHAIN=1 → login keychain cho CLI")
    func devLoginKeychain() throws {
        let dev = try RuntimeConfiguration.default(
            for: .cli, environment: ["KEYLOFT_DEV_LOGIN_KEYCHAIN": "1"])
        #expect(dev.keychain.useDataProtectionKeychain == false)

        let normal = try RuntimeConfiguration.default(
            for: .cli, environment: [:])
        #expect(normal.keychain.useDataProtectionKeychain == true)

        let app = try RuntimeConfiguration.default(for: .app, environment: [:])
        #expect(app.keychain.useDataProtectionKeychain == true)
    }
}
