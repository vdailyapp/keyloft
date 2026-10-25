import Foundation
import KeyloftTestSupport
import SecretVault
import Testing
import TokenVault
import VaultDomain

/// Store giả làm `set` (rotate) lỗi N lần đầu, sau đó delegate sang InMemorySecretStore.
final class FlakySecretStore: SecretStore, @unchecked Sendable {
    // NSLock + @unchecked Sendable — ngoại lệ Tests/.
    private let lock = NSLock()
    private var remainingFailures = 0
    private var setCountValue = 0
    let backing = InMemorySecretStore()

    func failNextSets(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        remainingFailures = count
    }

    var setCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return setCountValue
    }

    private func shouldFail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if remainingFailures > 0 {
            remainingFailures -= 1
            return true
        }
        return false
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func set(_ data: Data, for ref: KeychainRef, policy: SecretAccessPolicy) async throws {
        if shouldFail() {
            throw SecretStoreError.osStatus(-1)
        }
        _ = withLock { setCountValue += 1 }
        try await backing.set(data, for: ref, policy: policy)
    }

    func get(_ ref: KeychainRef, reason: String) async throws -> Data {
        try await backing.get(ref, reason: reason)
    }

    func delete(_ ref: KeychainRef) async throws {
        try await backing.delete(ref)
    }

    func contains(_ ref: KeychainRef) async throws -> Bool {
        try await backing.contains(ref)
    }
}

@Suite("TokenProvider")
struct TokenProviderTests {
    struct Rig {
        let db: InMemoryDatabase
        let audit: InMemoryAuditLog
        let clock: FixedDateProvider
        let stub: StubHTTPClient
        let registry: InMemoryProviderRegistry
        let vault: SecretVault
        let accounts: InMemoryAccountRepository
        let credentials: InMemoryCredentialRepository
        let metadata: InMemorySecretMetadataRepository
        let provider: TokenProvider
        let account: Account
        let credential: Credential
        let backingStore: InMemorySecretStore

        static func make(
            providerId: ProviderID = .microsoft,
            flaky: FlakySecretStore? = nil,
            granted: ScopeSet = ["openid", "offline_access", "Files.ReadWrite"]
        ) async throws -> Rig {
            let db = InMemoryDatabase()
            let audit = InMemoryAuditLog(db: db)
            let clock = FixedDateProvider()
            let backing = flaky?.backing ?? InMemorySecretStore()

            let client = TestData.oauthClient(provider: providerId, hasSecret: false)
            let account = TestData.account(provider: providerId, clientId: client.id)
            let secret = TestData.secret()
            let credential = TestData.credential(
                accountId: account.id, refreshTokenRef: secret.id,
                requested: granted, granted: granted)

            let clients = InMemoryOAuthClientRepository(db: db)
            let accounts = InMemoryAccountRepository(db: db)
            let credentials = InMemoryCredentialRepository(db: db)
            let metadata = InMemorySecretMetadataRepository(db: db)
            try await clients.save(client)
            try await accounts.save(account)
            try await metadata.insert(secret)
            try await credentials.insert(credential)
            // Refresh token ban đầu ghi thẳng vào store nền.
            try await backing.set(
                Data("rt-initial".utf8),
                for: KeychainRef(kind: .refreshToken, id: secret.id),
                policy: .afterFirstUnlock)

            let usedStore: any SecretStore = flaky ?? backing
            let vault = SecretVault(
                store: usedStore,
                metadata: metadata,
                audit: audit,
                clock: clock,
                ids: SequentialIDGenerator())
            let stub = StubHTTPClient()
            let registry = InMemoryProviderRegistry(TestData.allProviders)
            let provider = TokenProvider(
                providers: registry,
                clients: clients,
                accounts: accounts,
                credentials: credentials,
                secrets: vault,
                audit: audit,
                tokenEndpoint: TokenEndpointClient(http: stub),
                clock: clock,
                ids: SequentialIDGenerator())

            return Rig(
                db: db, audit: audit, clock: clock, stub: stub, registry: registry,
                vault: vault, accounts: accounts, credentials: credentials,
                metadata: metadata, provider: provider, account: account,
                credential: credential, backingStore: backing)
        }
    }

    @Test("U1: cache hit — 0 request")
    func cacheHit() async throws {
        let rig = try await Rig.make()
        await rig.provider.seed(
            AccessToken(value: "cached", scopes: [], expiresAt: rig.clock.now().addingTimeInterval(3600)),
            for: rig.account.id)

        let token = try await rig.provider.accessToken(for: rig.account.id)
        #expect(token.value == "cached")
        #expect(rig.stub.requests.isEmpty)
    }

    @Test("U2: gần hết hạn → refresh 1 lần, token mới")
    func nearExpiry() async throws {
        let rig = try await Rig.make()
        await rig.provider.seed(
            AccessToken(value: "old", scopes: [], expiresAt: rig.clock.now().addingTimeInterval(59)),
            for: rig.account.id)
        rig.stub.on(
            "POST", "https://example.test/microsoft/token",
            json: #"{"access_token":"new-at","token_type":"Bearer","expires_in":3600}"#)

        let token = try await rig.provider.accessToken(for: rig.account.id)
        #expect(token.value == "new-at")
        #expect(rig.stub.requests.count == 1)
        #expect(try await rig.provider.cachedToken(for: rig.account.id)?.value == "new-at")
    }

    @Test("U3: không có credential active → noActiveCredential")
    func noCredential() async throws {
        let rig = try await Rig.make()
        let empty = TestData.account(
            id: AccountID(rawValue: UUID()), clientId: TestData.oauthClient().id, externalId: "other")
        try await InMemoryAccountRepository(db: rig.db).save(empty)

        await #expect(throws: TokenVaultError.noActiveCredential(empty.id)) {
            _ = try await rig.provider.accessToken(for: empty.id)
        }
    }

    @Test("U4: 10 accessToken đồng thời, stub trễ 100ms → 1 request, kết quả bằng nhau")
    func singleFlight() async throws {
        let rig = try await Rig.make()
        rig.stub.on(
            "POST", "https://example.test/microsoft/token",
            json: #"{"access_token":"single","token_type":"Bearer"}"#,
            delay: .milliseconds(100))

        let tokens = try await withThrowingTaskGroup(of: AccessToken.self) { group in
            for _ in 0..<10 {
                group.addTask { try await rig.provider.accessToken(for: rig.account.id) }
            }
            var results: [AccessToken] = []
            while let token = try await group.next() { results.append(token) }
            return results
        }
        #expect(tokens.count == 10)
        #expect(Set(tokens.map(\.value)).count == 1)
        #expect(rig.stub.requests.count == 1)
    }

    @Test("U5: caller hủy giữa chừng — refresh vẫn hoàn tất, task sau nhận token")
    func callerCancelled() async throws {
        let rig = try await Rig.make()
        rig.stub.on(
            "POST", "https://example.test/microsoft/token",
            json: #"{"access_token":"done","refresh_token":"rt-2","token_type":"Bearer"}"#,
            delay: .milliseconds(150))

        let cancelled = Task { try await rig.provider.accessToken(for: rig.account.id) }
        // Chờ cho request đã tới stub (điểm chặn tất định, không sleep mù).
        while rig.stub.requests.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
        } catch is CancellationError {
            // kỳ vọng
        }

        let token = try await rig.provider.accessToken(for: rig.account.id)
        #expect(token.value == "done")
        #expect(rig.stub.requests.count == 1)

        // Secret đã xoay vòng.
        let value = try await rig.vault.read(rig.credential.refreshTokenRef, reason: "test", actor: .app)
        #expect(String(decoding: value, as: UTF8.self) == "rt-2")
    }

    @Test("U6: xoay vòng — secret thành rt2, rotatedAt set")
    func rotation() async throws {
        let rig = try await Rig.make()
        rig.stub.on(
            "POST", "https://example.test/microsoft/token",
            json: #"{"access_token":"at","refresh_token":"rt2","token_type":"Bearer"}"#)

        _ = try await rig.provider.accessToken(for: rig.account.id)
        let value = try await rig.vault.read(rig.credential.refreshTokenRef, reason: "t", actor: .app)
        #expect(String(decoding: value, as: UTF8.self) == "rt2")
        let metadata = try await InMemorySecretMetadataRepository(db: rig.db).get(rig.credential.refreshTokenRef)
        #expect(metadata?.rotatedAt != nil)
    }

    @Test("U7: rotate lỗi 2 lần rồi ok — thành công sau 3 lần set")
    func rotationRetry() async throws {
        let flaky = FlakySecretStore()
        let rig = try await Rig.make(flaky: flaky)
        flaky.failNextSets(2)
        rig.stub.on(
            "POST", "https://example.test/microsoft/token",
            json: #"{"access_token":"at","refresh_token":"rt-new","token_type":"Bearer"}"#)

        _ = try await rig.provider.accessToken(for: rig.account.id)
        #expect(flaky.setCount == 1)
        let value = try await rig.vault.read(rig.credential.refreshTokenRef, reason: "t", actor: .app)
        #expect(String(decoding: value, as: UTF8.self) == "rt-new")
    }

    @Test("U8: rotate lỗi 3 lần → rotationPersistFailed, account needsReauth")
    func rotationFailed() async throws {
        let flaky = FlakySecretStore()
        let rig = try await Rig.make(flaky: flaky)
        flaky.failNextSets(3)
        rig.stub.on(
            "POST", "https://example.test/microsoft/token",
            json: #"{"access_token":"at","refresh_token":"rt-new","token_type":"Bearer"}"#)

        await #expect(throws: TokenVaultError.rotationPersistFailed(rig.account.id)) {
            _ = try await rig.provider.accessToken(for: rig.account.id)
        }
        let account = try await InMemoryAccountRepository(db: rig.db).get(rig.account.id)
        #expect(account?.status == .needsReauth)
    }

    @Test("U9: lỗi tạm thời không đổi status, không audit")
    func transientNoStatusChange() async throws {
        let rig = try await Rig.make()
        rig.stub.on("POST", "https://example.test/microsoft/token", status: 503, json: "{}")

        do {
            _ = try await rig.provider.accessToken(for: rig.account.id)
            Issue.record("phải throw")
        } catch let error as TokenVaultError {
            guard case .oauth(let oauth) = error else {
                Issue.record("kỳ vọng .oauth, được \(error)")
                return
            }
            #expect(oauth == .server(status: 503))
            #expect(oauth.isTransient)
        }
        let account = try await InMemoryAccountRepository(db: rig.db).get(rig.account.id)
        #expect(account?.status == .healthy)
        let events = try await rig.audit.query(AuditQuery())
        #expect(events.filter { $0.action == .tokenRefreshFailed }.isEmpty)
    }

    @Test("U10: invalid_grant → needsReauth, cache rỗng, audit refresh_failed")
    func invalidGrant() async throws {
        let rig = try await Rig.make()
        await rig.provider.seed(
            AccessToken(value: "stale", scopes: [], expiresAt: rig.clock.now().addingTimeInterval(60)),
            for: rig.account.id)
        rig.stub.on(
            "POST", "https://example.test/microsoft/token", status: 400,
            json: #"{"error":"invalid_grant"}"#)

        await #expect(throws: TokenVaultError.oauth(.invalidGrant(nil))) {
            _ = try await rig.provider.accessToken(for: rig.account.id)
        }
        let account = try await InMemoryAccountRepository(db: rig.db).get(rig.account.id)
        #expect(account?.status == .needsReauth)
        #expect(await rig.provider.cachedToken(for: rig.account.id) == nil)
        let events = try await rig.audit.query(AuditQuery(actions: [.tokenRefreshFailed]))
        #expect(events.count == 1)
        #expect(events.first?.result == .failure(reason: "invalid_grant"))
    }

    @Test("U11: invalid_client → degraded + audit")
    func invalidClient() async throws {
        let rig = try await Rig.make()
        rig.stub.on(
            "POST", "https://example.test/microsoft/token", status: 401,
            json: #"{"error":"invalid_client"}"#)

        await #expect(throws: TokenVaultError.oauth(.invalidClient(nil))) {
            _ = try await rig.provider.accessToken(for: rig.account.id)
        }
        let account = try await InMemoryAccountRepository(db: rig.db).get(rig.account.id)
        #expect(account?.status == .degraded)
        #expect(try await rig.audit.query(AuditQuery(actions: [.tokenRefreshFailed])).count == 1)
    }

    @Test("U12: scope bị thu hẹp từ ngoài → updateGrantedScopes + audit scope.reduced")
    func scopeReduced() async throws {
        let rig = try await Rig.make(
            providerId: .google, granted: ["openid", "email", "drive"])
        rig.stub.on(
            "POST", "https://example.test/google/token",
            json: #"{"access_token":"at","token_type":"Bearer","scope":"openid email"}"#)

        _ = try await rig.provider.accessToken(for: rig.account.id)
        let credential = try await InMemoryCredentialRepository(db: rig.db).active(for: rig.account.id)
        #expect(credential?.grantedScopes == ["openid", "email"])
        let events = try await rig.audit.query(AuditQuery(actions: [.scopeReduced]))
        #expect(events.count == 1)
        #expect(events.first?.scopes == ["drive"])
    }

    @Test("U13: refreshIncludesScope — MS có scope trong body, Google không")
    func refreshIncludesScope() async throws {
        let ms = try await Rig.make(providerId: .microsoft)
        ms.stub.on(
            "POST", "https://example.test/microsoft/token",
            json: #"{"access_token":"at","token_type":"Bearer"}"#)
        _ = try await ms.provider.accessToken(for: ms.account.id)
        let msBody = String(decoding: ms.stub.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(msBody.contains("scope="))

        let google = try await Rig.make(providerId: .google, granted: ["openid", "email", "drive"])
        google.stub.on(
            "POST", "https://example.test/google/token",
            json: #"{"access_token":"at","token_type":"Bearer"}"#)
        _ = try await google.provider.accessToken(for: google.account.id)
        let googleBody = String(decoding: google.stub.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(!googleBody.contains("scope="))
    }

    @Test("U14: forceRefresh bỏ cache; đồng thời với accessToken vẫn 1 request")
    func forceRefresh() async throws {
        let rig = try await Rig.make()
        await rig.provider.seed(
            AccessToken(value: "still-valid", scopes: [], expiresAt: rig.clock.now().addingTimeInterval(3600)),
            for: rig.account.id)
        rig.stub.on(
            "POST", "https://example.test/microsoft/token",
            json: #"{"access_token":"fresh","token_type":"Bearer"}"#,
            delay: .milliseconds(50))

        async let forced: AccessToken = rig.provider.forceRefresh(for: rig.account.id)
        async let normal: AccessToken = rig.provider.accessToken(for: rig.account.id)
        let (f, n) = try await (forced, normal)
        // forceRefresh bỏ cache → token mới; accessToken chạy song song thấy cache còn hạn
        // nên trả cache — tổng số request vẫn 1 (đúng kỳ vọng single-flight).
        #expect(f.value == "fresh")
        #expect(n.value == "still-valid")
        #expect(rig.stub.requests.count == 1)
    }

    @Test("Property: 100 vòng lỗi tạm thời (seed cố định) — không bao giờ needsReauth")
    func transientProperty() async throws {
        let rig = try await Rig.make()
        let accounts = InMemoryAccountRepository(db: rig.db)
        let random = SeededRandomSource(seed: 2026)
        let payload = try random.bytes(count: 100)

        for byte in payload {
            let variant = byte % 4
            // Mỗi vòng một stub mới để route khớp đúng biến thể hiện tại.
            let fresh = StubHTTPClient()
            switch variant {
            case 0: fresh.on("POST", "https://example.test/microsoft/token", status: 503, json: "{}")
            case 1: fresh.on("POST", "https://example.test/microsoft/token", status: 500, json: "{}")
            case 2: fresh.onError("POST", "https://example.test/microsoft/token", URLError(.timedOut))
            default: fresh.onError("POST", "https://example.test/microsoft/token", URLError(.notConnectedToInternet))
            }
            let provider = TokenProvider(
                providers: rig.registry,
                clients: InMemoryOAuthClientRepository(db: rig.db),
                accounts: accounts,
                credentials: InMemoryCredentialRepository(db: rig.db),
                secrets: rig.vault,
                audit: rig.audit,
                tokenEndpoint: TokenEndpointClient(http: fresh),
                clock: rig.clock,
                ids: SequentialIDGenerator())
            do {
                _ = try await provider.accessToken(for: rig.account.id)
            } catch let error as TokenVaultError {
                guard case .oauth(let oauth) = error, oauth.isTransient else {
                    Issue.record("kỳ vọng lỗi tạm thời, được \(error)")
                    return
                }
            }
            let account = try await accounts.get(rig.account.id)
            #expect(account?.status != .needsReauth)
            if account?.status == .needsReauth { return }
        }
    }

    @Test("Edge: expires_in thiếu → hạn +3600")
    func missingExpiresIn() async throws {
        let rig = try await Rig.make()
        rig.stub.on(
            "POST", "https://example.test/microsoft/token",
            json: #"{"access_token":"at","token_type":"Bearer"}"#)
        let token = try await rig.provider.accessToken(for: rig.account.id)
        #expect(token.expiresAt == rig.clock.now().addingTimeInterval(3600))
    }
}
