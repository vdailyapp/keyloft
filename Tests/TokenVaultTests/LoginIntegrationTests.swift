import Foundation
import KeyloftTestSupport
import SecretVault
import Testing
import TokenVault
import VaultDomain

@Suite("Login integration")
struct LoginIntegrationTests {
    /// I2: OAuthLoginService + LoopbackServer thật + FakeBrowserSession + StubHTTPClient.
    @Test("I2: end-to-end không mạng ngoài; redirect_uri exchange đúng redirect thật")
    func endToEnd() async throws {
        let db = InMemoryDatabase()
        let audit = InMemoryAuditLog(db: db)
        let clock = FixedDateProvider()
        let clients = InMemoryOAuthClientRepository(db: db)
        let accounts = InMemoryAccountRepository(db: db)
        let credentials = InMemoryCredentialRepository(db: db)
        let metadata = InMemorySecretMetadataRepository(db: db)
        let store = InMemorySecretStore()
        let vault = SecretVault(
            store: store, metadata: metadata, audit: audit,
            clock: clock, ids: SequentialIDGenerator())
        let registry = InMemoryProviderRegistry(TestData.allProviders)

        let client = TestData.oauthClient(hasSecret: false)
        try await clients.save(client)

        let provider = try await registry.provider(client.providerId)
        let idToken = TestJWT.make(
            claims: TestJWT.claims(iss: provider.issuer, sub: "sub-e2e", aud: [client.clientId]))
        let stub = StubHTTPClient()
        stub.on(
            "POST", provider.tokenURL.absoluteString,
            json:
                #"{"access_token":"e2e-at","token_type":"Bearer","refresh_token":"e2e-rt","expires_in":3600,"scope":"openid https://www.googleapis.com/auth/userinfo.email drive","id_token":""#
                + idToken + #""}"#)

        let service = OAuthLoginService(
            providers: registry,
            clients: clients,
            accounts: accounts,
            credentials: credentials,
            secrets: vault,
            audit: audit,
            tokenEndpoint: TokenEndpointClient(http: stub),
            browser: FakeBrowserSession(behavior: .redirect(code: "e2e-code", state: .echo, iss: nil)),
            receivers: { configured in
                LoopbackServer(configuredRedirect: configured, timeout: .seconds(10))
            },
            random: SeededRandomSource(seed: 11),
            clock: clock,
            ids: SequentialIDGenerator())

        let outcome = try await service.login(
            LoginRequest(
                oauthClientId: client.id,
                scopes: ["openid", "email", "drive"],
                target: .newAccount))
        #expect(outcome.isNewAccount)
        #expect(outcome.account.status == .healthy)
        #expect(outcome.account.externalId == "sub-e2e")

        // redirect_uri gửi lúc exchange == redirect thật có port của loopback.
        let body = String(decoding: stub.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A"))
        #expect(body.contains("%2Fcallback"))
        #expect(body.contains("code=e2e-code"))
        #expect(body.contains("code_verifier="))

        let secretValue = try await vault.read(
            outcome.credential.refreshTokenRef, reason: "test", actor: .app)
        #expect(String(decoding: secretValue, as: UTF8.self) == "e2e-rt")
    }

    /// Edge: 2 login song song cùng client — 2 loopback port khác nhau, 2 state, không lẫn.
    @Test("Hai login song song cùng client → 2 account, state/callback không lẫn")
    func parallelLogins() async throws {
        let db = InMemoryDatabase()
        let audit = InMemoryAuditLog(db: db)
        let clock = FixedDateProvider()
        let clients = InMemoryOAuthClientRepository(db: db)
        let accounts = InMemoryAccountRepository(db: db)
        let credentials = InMemoryCredentialRepository(db: db)
        let metadata = InMemorySecretMetadataRepository(db: db)
        let store = InMemorySecretStore()
        let vault = SecretVault(
            store: store, metadata: metadata, audit: audit,
            clock: clock, ids: SequentialIDGenerator())
        let registry = InMemoryProviderRegistry(TestData.allProviders)
        let client = TestData.oauthClient(hasSecret: false)
        try await clients.save(client)
        let provider = try await registry.provider(client.providerId)

        // Token endpoint trả id_token sub theo code → phân biệt 2 luồng.
        let stub = StubHTTPClient()
        stub.add(
            StubHTTPClient.Route(method: "POST", urlPrefix: provider.tokenURL.absoluteString) { request in
                let body = String(
                    decoding: request.httpBody ?? Data(), as: UTF8.self)
                let code =
                    body.split(separator: "&").first { $0.hasPrefix("code=") }.map {
                        String($0.dropFirst(5))
                    } ?? "unknown"
                let sub = "sub-\(code)"
                let idToken = TestJWT.make(
                    claims: TestJWT.claims(iss: provider.issuer, sub: sub, aud: [client.clientId]))
                let json =
                    #"{"access_token":"at-\#(code)","token_type":"Bearer","refresh_token":"rt-\#(code)","expires_in":3600,"scope":"openid https://www.googleapis.com/auth/userinfo.email drive","id_token":"\#(idToken)"}"#
                return (200, ["Content-Type": "application/json"], Data(json.utf8))
            })

        // Hai service dùng chung generator để không đụng ID trong repo dùng chung.
        let sharedIDs = SequentialIDGenerator()
        func makeService(code: String) -> OAuthLoginService {
            OAuthLoginService(
                providers: registry,
                clients: clients,
                accounts: accounts,
                credentials: credentials,
                secrets: vault,
                audit: audit,
                tokenEndpoint: TokenEndpointClient(http: stub),
                browser: FakeBrowserSession(behavior: .redirect(code: code, state: .echo, iss: nil)),
                receivers: { configured in
                    LoopbackServer(configuredRedirect: configured, timeout: .seconds(10))
                },
                random: SeededRandomSource(seed: UInt64.random(in: 1...1000)),
                clock: clock,
                ids: sharedIDs)
        }

        async let first: LoginOutcome = makeService(code: "AAA").login(
            LoginRequest(oauthClientId: client.id, scopes: ["openid", "email"], target: .newAccount))
        async let second: LoginOutcome = makeService(code: "BBB").login(
            LoginRequest(oauthClientId: client.id, scopes: ["openid", "email"], target: .newAccount))
        let (a, b) = try await (first, second)

        #expect(a.account.externalId == "sub-AAA")
        #expect(b.account.externalId == "sub-BBB")
        #expect(a.account.id != b.account.id)
        let all = try await accounts.list()
        #expect(all.count == 2)
        let tokenRequests = stub.requests
        #expect(tokenRequests.count == 2)
        let codes = Set(
            tokenRequests.map { request in
                String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                    .split(separator: "&").first { $0.hasPrefix("code=") }.map(String.init) ?? ""
            })
        #expect(codes == ["code=AAA", "code=BBB"])
    }
}
