import Foundation
import KeyloftTestSupport
import SecretVault
import Testing
import TokenVault
import VaultDomain

/// Credential repo fail-on-demand (U41).
final class FlakyCredentialRepo: CredentialRepository, @unchecked Sendable {
    // NSLock + @unchecked Sendable — ngoại lệ Tests/.
    private let lock = NSLock()
    private var failInsert = false
    let backing: InMemoryCredentialRepository

    init(db: InMemoryDatabase) {
        backing = InMemoryCredentialRepository(db: db)
    }

    func failNextInsert() {
        withLock { failInsert = true }
    }

    func insert(_ credential: Credential) async throws {
        if withLock({
            if failInsert {
                failInsert = false
                return true
            }
            return false
        }) {
            throw DomainError.invariantViolated("insert fail theo yêu cầu test")
        }
        try await backing.insert(credential)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func get(_ id: CredentialID) async throws -> Credential? { try await backing.get(id) }
    func active(for account: AccountID) async throws -> Credential? {
        try await backing.active(for: account)
    }
    func list(for account: AccountID) async throws -> [Credential] {
        try await backing.list(for: account)
    }
    func markSuperseded(_ id: CredentialID, by newId: CredentialID) async throws {
        try await backing.markSuperseded(id, by: newId)
    }
    func markRevoked(_ id: CredentialID) async throws { try await backing.markRevoked(id) }
    func updateGrantedScopes(_ id: CredentialID, _ scopes: ScopeSet) async throws {
        try await backing.updateGrantedScopes(id, scopes)
    }
}

/// Receiver "echo" cho unit test: state thật lấy từ URL mà FakeBrowserSession đã mở
/// (đúng như luồng thật — state đi qua trình duyệt rồi quay về callback).
final class BrowserEchoReceiver: CallbackReceiver, @unchecked Sendable {
    // NSLock + @unchecked Sendable — ngoại lệ Tests/.
    private let lock = NSLock()
    private var startCountValue = 0
    private var stopCountValue = 0
    let browser: FakeBrowserSession
    /// code/iss/error dùng trực tiếp; state luôn parse từ authorize URL.
    var overrides: CallbackParameters
    /// Số URL đã tiêu thụ — mỗi lần login dùng authorize URL mới nhất chưa dùng.
    private var consumed = 0

    init(browser: FakeBrowserSession, overrides: CallbackParameters) {
        self.browser = browser
        self.overrides = overrides
    }

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return startCountValue
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stopCountValue
    }

    func start() async throws -> URL {
        withLock { startCountValue += 1 }
        return URL(string: "http://127.0.0.1:55555/callback")!
    }

    func waitForCallback() async throws -> CallbackParameters {
        // Chờ authorize URL mới chưa tiêu thụ (service gọi present song song).
        while true {
            let urls = browser.openedURLs
            if urls.count > consumed {
                let url = urls[consumed]
                consumed += 1
                let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "state" })?.value
                return CallbackParameters(
                    code: overrides.code,
                    // state nil → echo state thật từ browser; đặt trước → giả lập lệch state.
                    state: overrides.state ?? state,
                    iss: overrides.iss,
                    error: overrides.error,
                    errorDescription: overrides.errorDescription)
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func stop() async {
        withLock { stopCountValue += 1 }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@Suite("OAuthLoginService")
struct OAuthLoginServiceTests {
    struct Rig {
        let db: InMemoryDatabase
        let store: InMemorySecretStore
        let audit: InMemoryAuditLog
        let clock: FixedDateProvider
        let stub: StubHTTPClient
        let registry: InMemoryProviderRegistry
        let clients: InMemoryOAuthClientRepository
        let accounts: InMemoryAccountRepository
        let metadata: InMemorySecretMetadataRepository
        let vault: SecretVault
        let receiver: BrowserEchoReceiver
        let browser: FakeBrowserSession
        let service: OAuthLoginService
        let client: OAuthClient

        static func make(
            providerId: ProviderID = .google,
            iss: String? = nil,
            receiverParameters: CallbackParameters? = nil,
            browserBehavior: FakeBrowserSession.Behavior? = nil,
            tokenResponseJSON: String? = nil,
            responseScope: String = "openid https://www.googleapis.com/auth/userinfo.email drive",
            clientHasSecret: Bool = false,
            flakyCredentials: FlakyCredentialRepo? = nil,
            observer: CredentialIssuedObserver? = nil
        ) async throws -> Rig {
            let db = InMemoryDatabase()
            let audit = InMemoryAuditLog(db: db)
            let clock = FixedDateProvider()
            let registry = InMemoryProviderRegistry(TestData.allProviders)
            let clients = InMemoryOAuthClientRepository(db: db)
            let accounts = InMemoryAccountRepository(db: db)
            let credentials: any CredentialRepository = flakyCredentials ?? FlakyCredentialRepo(db: db)
            let metadata = InMemorySecretMetadataRepository(db: db)
            let store = InMemorySecretStore()
            let vault = SecretVault(
                store: store, metadata: metadata, audit: audit,
                clock: clock, ids: SequentialIDGenerator())

            let client = TestData.oauthClient(provider: providerId, hasSecret: clientHasSecret)
            try await clients.save(client)
            if clientHasSecret, let secretRef = client.clientSecretRef {
                try await metadata.insert(
                    TestData.secret(id: secretRef, kind: .clientSecret, label: "cs"))
                try await store.set(
                    Data("super-secret-cs".utf8),
                    for: KeychainRef(kind: .clientSecret, id: secretRef),
                    policy: .afterFirstUnlock)
            }

            let browser = FakeBrowserSession(
                behavior: browserBehavior ?? .redirect(code: "code-1", state: .echo, iss: iss))
            let receiver = BrowserEchoReceiver(
                browser: browser,
                overrides: receiverParameters ?? CallbackParameters(code: "code-1", iss: iss))

            let provider = try await registry.provider(providerId)
            let idToken = TestJWT.make(
                claims: TestJWT.claims(iss: provider.issuer, sub: "sub-1", aud: [client.clientId]))
            let json =
                tokenResponseJSON
                ?? #"{"access_token":"at-1","token_type":"Bearer","refresh_token":"rt-1","expires_in":3600,"scope":""#
                + responseScope + #"","id_token":""# + idToken + #""}"#
            let stub = StubHTTPClient()
            stub.on("POST", provider.tokenURL.absoluteString, json: json)

            let service = OAuthLoginService(
                providers: registry,
                clients: clients,
                accounts: accounts,
                credentials: credentials,
                secrets: vault,
                audit: audit,
                tokenEndpoint: TokenEndpointClient(http: stub),
                browser: browser,
                receivers: { _ in receiver },
                random: SeededRandomSource(seed: 7),
                clock: clock,
                ids: SequentialIDGenerator(),
                onCredentialIssued: observer)

            return Rig(
                db: db, store: store, audit: audit, clock: clock, stub: stub,
                registry: registry, clients: clients, accounts: accounts,
                metadata: metadata, vault: vault, receiver: receiver, browser: browser,
                service: service, client: client)
        }
    }

    @Test("U33: happy path account mới — healthy, 1 credential, 1 secret, audit đủ")
    func happyPath() async throws {
        let rig = try await Rig.make()
        let outcome = try await rig.service.login(
            LoginRequest(
                oauthClientId: rig.client.id,
                scopes: ["openid", "email", "drive"],
                target: .newAccount))

        #expect(outcome.isNewAccount)
        #expect(outcome.account.status == .healthy)
        #expect(outcome.deniedScopes.isEmpty)
        #expect(try await rig.credentials(rig).list(for: outcome.account.id).count == 1)
        #expect(try await rig.credentials(rig).active(for: outcome.account.id)?.id == outcome.credential.id)
        let secrets = try await rig.metadata.list(kind: .refreshToken)
        #expect(secrets.count == 1)
        let actions = try await rig.audit.query(AuditQuery()).map(\.action)
        #expect(actions.contains(.accountAdded))
        #expect(actions.contains(.credentialIssued))
        #expect(actions.contains(.scopeGranted))
    }

    @Test("U34: state sai → stateMismatch, 0 request token, audit failure, không account/secret")
    func stateMismatch() async throws {
        let rig = try await Rig.make(
            receiverParameters: CallbackParameters(code: "c", state: "tampered", iss: nil))
        await #expect(throws: OAuthError.stateMismatch) {
            _ = try await rig.service.login(
                LoginRequest(oauthClientId: rig.client.id, scopes: ["openid"], target: .newAccount))
        }
        #expect(rig.stub.requests.isEmpty)
        let failures = try await rig.audit.query(AuditQuery(actions: [.credentialIssued]))
        #expect(failures.first?.result == .failure(reason: "state mismatch"))
        #expect(try await rig.accounts.list().isEmpty)
        #expect(try await rig.metadata.list(kind: nil).isEmpty)
    }

    @Test("U35: iss sai / thiếu khi bắt buộc → issuerMismatch, 0 request token")
    func issuerMismatch() async throws {
        let wrongIss = try await Rig.make(providerId: .microsoft, iss: "https://evil.example")
        await #expect(
            throws: OAuthError.issuerMismatch(
                expected: TestData.microsoftProvider.issuer, actual: "https://evil.example")
        ) {
            _ = try await wrongIss.service.login(
                LoginRequest(oauthClientId: wrongIss.client.id, scopes: ["openid"], target: .newAccount))
        }
        #expect(wrongIss.stub.requests.isEmpty)

        // Microsoft: authorizationResponseIssSupported = true (TestData) → iss thiếu là lỗi.
        let missingIss = try await Rig.make(providerId: .microsoft, iss: nil)
        await #expect(
            throws: OAuthError.issuerMismatch(
                expected: TestData.microsoftProvider.issuer, actual: nil)
        ) {
            _ = try await missingIss.service.login(
                LoginRequest(oauthClientId: missingIss.client.id, scopes: ["openid"], target: .newAccount))
        }
        #expect(missingIss.stub.requests.isEmpty)
    }

    @Test("U36: access_denied → .accessDenied, không ghi gì")
    func accessDenied() async throws {
        let rig = try await Rig.make(
            receiverParameters: CallbackParameters(
                error: "access_denied", errorDescription: "user said no"))
        await #expect(throws: OAuthError.accessDenied("user said no")) {
            _ = try await rig.service.login(
                LoginRequest(oauthClientId: rig.client.id, scopes: ["openid"], target: .newAccount))
        }
        #expect(rig.stub.requests.isEmpty)
        #expect(try await rig.accounts.list().isEmpty)
        #expect(try await rig.metadata.list(kind: nil).isEmpty)
    }

    @Test("U37: thiếu refresh_token → .missingRefreshToken, không secret")
    func missingRefreshToken() async throws {
        let rig = try await Rig.make(
            tokenResponseJSON: #"{"access_token":"at","token_type":"Bearer","id_token":"x.y.z"}"#)
        await #expect(throws: OAuthError.missingRefreshToken) {
            _ = try await rig.service.login(
                LoginRequest(oauthClientId: rig.client.id, scopes: ["openid"], target: .newAccount))
        }
        #expect(try await rig.metadata.list(kind: .refreshToken).isEmpty)
    }

    @Test("U38: scope bị bỏ tick → needsConsent, deniedScopes [drive], audit scope.denied")
    func scopeDenied() async throws {
        let rig = try await Rig.make(
            responseScope: "openid https://www.googleapis.com/auth/userinfo.email")
        let outcome = try await rig.service.login(
            LoginRequest(
                oauthClientId: rig.client.id,
                scopes: ["openid", "email", "drive"],
                target: .newAccount))
        #expect(outcome.account.status == .needsConsent)
        #expect(outcome.deniedScopes == ["drive"])
        #expect(
            outcome.credential.grantedScopes == [
                "openid", "https://www.googleapis.com/auth/userinfo.email",
            ])
        let denied = try await rig.audit.query(AuditQuery(actions: [.scopeDenied]))
        #expect(denied.count == 1)
        #expect(denied.first?.scopes == ["drive"])
    }

    @Test("U39: đăng nhập lại cùng sub → 1 account, 2 credential, c1 superseded by c2")
    func reloginSameSub() async throws {
        let rig = try await Rig.make()
        let first = try await rig.service.login(
            LoginRequest(oauthClientId: rig.client.id, scopes: ["openid", "email", "drive"], target: .newAccount))
        let second = try await rig.service.login(
            LoginRequest(oauthClientId: rig.client.id, scopes: ["openid", "email", "drive"], target: .newAccount))

        #expect(!second.isNewAccount)
        #expect(try await rig.accounts.list().count == 1)
        let credentials = try await rig.credentials(rig).list(for: first.account.id)
        #expect(credentials.count == 2)
        let superseded = try await rig.credentials(rig).get(first.credential.id)
        #expect(superseded?.status == .superseded)
        #expect(superseded?.supersededBy == second.credential.id)
        #expect(try await rig.audit.query(AuditQuery(actions: [.credentialSuperseded])).count == 1)
    }

    @Test("U40: .existing sai sub → accountMismatch, account không đổi, 0 secret mới")
    func wrongAccount() async throws {
        let rig = try await Rig.make()
        // Account A có sub khác (sub-A).
        let accountA = TestData.account(
            id: AccountID(rawValue: UUID()), clientId: rig.client.id, externalId: "sub-A")
        try await rig.accounts.save(accountA)

        await #expect(
            throws: OAuthError.accountMismatch(
                expectedExternalId: "sub-A", actualEmail: "user@example.test")
        ) {
            _ = try await rig.service.login(
                LoginRequest(oauthClientId: rig.client.id, scopes: ["openid"], target: .existing(accountA.id)))
        }
        let unchanged = try await rig.accounts.get(accountA.id)
        #expect(unchanged?.externalId == "sub-A")
        let secrets = try await rig.metadata.list(kind: .refreshToken)
        // Secret mồi côi phải bị bồi hoàn: không secret refreshToken nào tồn tại.
        #expect(try await rig.store.storedRefs.filter { $0.account.hasPrefix("refreshToken") }.isEmpty)
    }

    @Test("U41: lỗi sau khi tạo secret → bồi hoàn xóa secret + metadata")
    func compensatesSecret() async throws {
        let db = InMemoryDatabase()
        let flaky = FlakyCredentialRepo(db: db)
        let rig = try await Rig.make(flakyCredentials: flaky)
        flaky.failNextInsert()

        await #expect(throws: DomainError.invariantViolated("insert fail theo yêu cầu test")) {
            _ = try await rig.service.login(
                LoginRequest(oauthClientId: rig.client.id, scopes: ["openid"], target: .newAccount))
        }
        let refs = await rig.store.storedRefs
        #expect(refs.filter { $0.account.hasPrefix("refreshToken") }.isEmpty)
        #expect(try await rig.metadata.list(kind: .refreshToken).isEmpty)
    }

    @Test("U42: người dùng hủy trình duyệt → userCancelled, receiver stop() được gọi")
    func userCancelled() async throws {
        let rig = try await Rig.make(browserBehavior: .cancel)
        await #expect(throws: OAuthError.userCancelled) {
            _ = try await rig.service.login(
                LoginRequest(oauthClientId: rig.client.id, scopes: ["openid"], target: .newAccount))
        }
        #expect(rig.receiver.stopCount == 1)
    }

    @Test("U43: browser present xong trước khi callback xử lý xong → vẫn thành công")
    func browserFinishesEarly() async throws {
        // FakeBrowserSession ghi openedURL và GET xong mới return; receiver chờ openedURL
        // bằng vòng poll — trình tự hai bên chạy song song độc lập, luồng vẫn hoàn tất.
        let rig = try await Rig.make()
        let outcome = try await rig.service.login(
            LoginRequest(oauthClientId: rig.client.id, scopes: ["openid", "email", "drive"], target: .newAccount))
        #expect(outcome.account.status == .healthy)
        #expect(rig.browser.openedURLs.count == 1)
    }

    @Test("U44: client secret đọc từ SecretVault, secretRead không audit (actor .app)")
    func clientSecretFromVault() async throws {
        let rig = try await Rig.make(clientHasSecret: true)
        let outcome = try await rig.service.login(
            LoginRequest(oauthClientId: rig.client.id, scopes: ["openid", "email", "drive"], target: .newAccount))
        #expect(outcome.isNewAccount)
        let body = String(decoding: rig.stub.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("client_secret=super-secret-cs"))
        let reads = try await rig.audit.query(AuditQuery(actions: [.secretRead]))
        #expect(reads.isEmpty)
    }

    @Test("U45: observer được gọi 1 lần, expiresAt = now + expires_in")
    func observerSeedsToken() async throws {
        let box = ObserverBox()
        let rig = try await Rig.make(observer: { account, token in
            await box.record(account, token)
        })
        let outcome = try await rig.service.login(
            LoginRequest(oauthClientId: rig.client.id, scopes: ["openid", "email", "drive"], target: .newAccount))
        let calls = await box.calls
        #expect(calls.count == 1)
        #expect(calls.first?.0 == outcome.account.id)
        #expect(calls.first?.1.expiresAt == rig.clock.now().addingTimeInterval(3600))
        #expect(calls.first?.1.value == "at-1")
    }
}

actor ObserverBox {
    private(set) var calls: [(AccountID, AccessToken)] = []

    func record(_ account: AccountID, _ token: AccessToken) {
        calls.append((account, token))
    }
}

extension OAuthLoginServiceTests.Rig {
    /// Repo credential gốc của rig (không phải flaky).
    func credentials(_ rig: OAuthLoginServiceTests.Rig) -> InMemoryCredentialRepository {
        InMemoryCredentialRepository(db: rig.db)
    }
}
