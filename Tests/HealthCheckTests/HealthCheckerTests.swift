import Foundation
import HealthCheck
import KeyloftTestSupport
import Providers
import SecretVault
import Testing
import TokenVault
import VaultDomain

@Suite("HealthChecker")
struct HealthCheckerTests {
    struct Rig {
        let db: InMemoryDatabase
        let store: InMemorySecretStore
        let audit: InMemoryAuditLog
        let clock: FixedDateProvider
        let stub: StubHTTPClient
        let registry: InMemoryProviderRegistry
        let clients: InMemoryOAuthClientRepository
        let accounts: InMemoryAccountRepository
        let credentials: InMemoryCredentialRepository
        let metadata: InMemorySecretMetadataRepository
        let results: InMemoryHealthCheckRepository
        let probe: FakeProbe
        let checker: HealthChecker
        let account: Account
        let credential: Credential
        let client: OAuthClient

        static func make(
            granted: ScopeSet = ["openid", "https://www.googleapis.com/auth/userinfo.email", "drive"],
            probe: FakeProbe = FakeProbe.ok(),
            clientSecretExpiresIn: TimeInterval? = nil
        ) async throws -> Rig {
            let db = InMemoryDatabase()
            let audit = InMemoryAuditLog(db: db)
            let clock = FixedDateProvider()
            let store = InMemorySecretStore()
            let registry = InMemoryProviderRegistry(TestData.allProviders)
            let clients = InMemoryOAuthClientRepository(db: db)
            let accounts = InMemoryAccountRepository(db: db)
            let credentials = InMemoryCredentialRepository(db: db)
            let metadata = InMemorySecretMetadataRepository(db: db)
            let results = InMemoryHealthCheckRepository(db: db)

            var client = TestData.oauthClient(hasSecret: false)
            if let expiresIn = clientSecretExpiresIn {
                client.secretExpiresAt = clock.now().addingTimeInterval(expiresIn)
            }
            try await clients.save(client)
            let account = TestData.account(clientId: client.id)
            try await accounts.save(account)
            let secret = TestData.secret()
            try await metadata.insert(secret)
            try await store.set(
                Data("rt-1".utf8), for: secret.keychainRef, policy: .afterFirstUnlock)
            let credential = TestData.credential(
                accountId: account.id, refreshTokenRef: secret.id,
                requested: granted, granted: granted)
            try await credentials.insert(credential)

            let vault = SecretVault(
                store: store, metadata: metadata, audit: audit,
                clock: clock, ids: SequentialIDGenerator())
            // Stub đăng ký route THÀNH CÔNG mặc định; test muốn lỗi đổi sang stub riêng
            // (route đầu tiên thắng) — dùng refreshStub riêng mỗi nhu cầu.
            let stubHTTP = StubHTTPClient()
            let tokens = TokenProvider(
                providers: registry, clients: clients, accounts: accounts,
                credentials: credentials, secrets: vault, audit: audit,
                tokenEndpoint: TokenEndpointClient(http: stubHTTP), clock: clock,
                ids: SequentialIDGenerator())

            let checker = HealthChecker(
                accounts: accounts,
                credentials: credentials,
                clients: clients,
                secretExists: { id in
                    guard let secret = try await metadata.get(id) else { return false }
                    return try await store.contains(secret.keychainRef)
                },
                tokens: tokens,
                providers: registry,
                probes: { _ in probe },
                results: results,
                audit: audit,
                clock: clock,
                ids: SequentialIDGenerator())

            return Rig(
                db: db, store: store, audit: audit, clock: clock, stub: stubHTTP,
                registry: registry, clients: clients, accounts: accounts,
                credentials: credentials, metadata: metadata, results: results,
                probe: probe, checker: checker, account: account, credential: credential,
                client: client)
        }

        /// Route refresh thành công (test gọi khi cần tầng 2 qua).
        func happyRefresh() {
            stub.on(
                "POST", "https://example.test/google/token",
                json: #"{"access_token":"at-1","token_type":"Bearer","expires_in":3600}"#)
        }
    }

    @Test("U2: không có credential → needsReauth, checks == [tokenPresent(ok:false)]")
    func noCredential() async throws {
        let rig = try await Rig.make()
        let empty = TestData.account(
            id: AccountID(rawValue: UUID()), clientId: rig.client.id, externalId: "none")
        try await rig.accounts.save(empty)

        let result = try await rig.checker.check(empty.id, actor: .scheduler)
        #expect(result.status == .needsReauth)
        #expect(result.checks == [HealthCheckItem(name: .tokenPresent, ok: false, error: "noRefreshToken")])
    }

    @Test("U3: Keychain mất item → needsReauth, chỉ 1 tầng")
    func secretMissing() async throws {
        let rig = try await Rig.make()
        await rig.store.remove(KeychainRef(kind: .refreshToken, id: rig.credential.refreshTokenRef))
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .needsReauth)
        #expect(result.checks.count == 1)
        #expect(result.checks.first?.ok == false)
    }

    @Test("U4: invalid_grant → needsReauth, 2 tầng, probe 0 lần")
    func invalidGrant() async throws {
        let rig = try await Rig.make()
        rig.stub.on(
            "POST", "https://example.test/google/token", status: 400,
            json: #"{"error":"invalid_grant"}"#)
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .needsReauth)
        #expect(result.checks.count == 2)
        #expect(rig.probe.calls == 0)
    }

    @Test("U5: invalid_client → degraded")
    func invalidClient() async throws {
        let rig = try await Rig.make()
        rig.stub.on(
            "POST", "https://example.test/google/token", status: 401,
            json: #"{"error":"invalid_client"}"#)
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .degraded)
    }

    @Test("U6: refresh 503 → unreachable")
    func refreshServer() async throws {
        let rig = try await Rig.make()
        rig.stub.on("POST", "https://example.test/google/token", status: 503, json: "{}")
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .unreachable)
    }

    @Test("U7: Keychain khóa (interactionNotAllowed) → unreachable, KHÔNG needsReauth")
    func keychainLocked() async throws {
        // Mô phỏng máy khóa: store get throw interactionNotAllowed — TokenProvider đọc
        // refresh token thất bại nhưng KHÔNG phải vì token hết hạn.
        let rig = try await Rig.make()
        rig.happyRefresh()
        let locked = LockingStore(wrapping: rig.store)
        let vault = SecretVault(
            store: locked,
            metadata: rig.metadata,
            audit: rig.audit,
            clock: rig.clock,
            ids: SequentialIDGenerator())
        let tokens = TokenProvider(
            providers: rig.registry, clients: rig.clients, accounts: rig.accounts,
            credentials: rig.credentials, secrets: vault, audit: rig.audit,
            tokenEndpoint: TokenEndpointClient(http: rig.stub), clock: rig.clock,
            ids: SequentialIDGenerator())
        let checker = HealthChecker(
            accounts: rig.accounts, credentials: rig.credentials, clients: rig.clients,
            secretExists: { _ in true },
            tokens: tokens, providers: rig.registry, probes: { _ in rig.probe },
            results: rig.results, audit: rig.audit, clock: rig.clock,
            ids: SequentialIDGenerator())
        let result = try await checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .unreachable)
        #expect(result.checks.last?.error == "refreshTransient(secretUnavailable)")
    }

    @Test("U8: probe 403 insufficientScope → needsConsent, 3 tầng")
    func probeInsufficient() async throws {
        let probe = FakeProbe.ok()
        probe.fail(with: .insufficientScope("drive"))
        let rig = try await Rig.make(probe: probe)
        rig.happyRefresh()
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .needsConsent)
        #expect(result.checks.count == 3)
    }

    @Test("U9: probe 401 → degraded")
    func probeUnauthorized() async throws {
        let probe = FakeProbe.ok()
        probe.fail(with: .unauthorized)
        let rig = try await Rig.make(probe: probe)
        rig.happyRefresh()
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .degraded)
    }

    @Test("U10: probe 429 / network → unreachable")
    func probeTransient() async throws {
        for error in [ProbeError.rateLimited, ProbeError.network(.timedOut)] {
            let probe = FakeProbe.ok()
            probe.fail(with: error)
            let rig = try await Rig.make(probe: probe)
            rig.happyRefresh()
            let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
            #expect(result.status == .unreachable)
        }
    }

    @Test("U11: thiếu scope cần → needsConsent, error nêu scope thiếu")
    func missingScopes() async throws {
        let rig = try await Rig.make(granted: ["openid", "https://www.googleapis.com/auth/userinfo.email"])
        rig.happyRefresh()
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .needsConsent)
        let scopesItem = result.checks.first { $0.name == .scopes }
        #expect(scopesItem?.ok == false)
        #expect(scopesItem?.error == "missingScopes(drive)")
    }

    @Test("U12: quota 95% → degraded + warning quota>90%, đủ 5 tầng")
    func quotaWarning() async throws {
        let probe = FakeProbe.ok(used: 95, total: 100)
        let rig = try await Rig.make(probe: probe)
        rig.happyRefresh()
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .degraded)
        #expect(result.checks.count == 5)
        let early = result.checks.first { $0.name == .earlyWarning }
        #expect(early?.warnings == ["quota>90%"])
    }

    @Test("U13: quota không giới hạn → không cảnh báo")
    func unlimitedQuota() async throws {
        let probe = FakeProbe.ok(used: 95, total: nil)
        let rig = try await Rig.make(probe: probe)
        rig.happyRefresh()
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .healthy)
    }

    @Test("U14: client secret 29 ngày / hết hạn / 31 ngày")
    func secretExpiry() async throws {
        let soon = try await Rig.make(clientSecretExpiresIn: 29 * 86_400)
        soon.happyRefresh()
        let soonResult = try await soon.checker.check(soon.account.id, actor: .scheduler)
        #expect(soonResult.status == .degraded)
        #expect(soonResult.checks.last?.warnings.contains("clientSecret<30d") == true)

        let expired = try await Rig.make(clientSecretExpiresIn: -1)
        expired.happyRefresh()
        let expiredResult = try await expired.checker.check(expired.account.id, actor: .scheduler)
        #expect(expiredResult.status == .degraded)
        #expect(expiredResult.checks.last?.warnings.contains("clientSecretExpired") == true)

        let far = try await Rig.make(clientSecretExpiresIn: 31 * 86_400)
        far.happyRefresh()
        let farResult = try await far.checker.check(far.account.id, actor: .scheduler)
        #expect(farResult.status == .healthy)
    }

    @Test("U15: probe chậm 3001ms → degraded + slow")
    func slowProbe() async throws {
        let probe = FakeProbe.ok(latencyMs: 3001)
        let rig = try await Rig.make(probe: probe)
        rig.happyRefresh()
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .degraded)
        #expect(result.checks.last?.warnings.contains("slow") == true)
    }

    @Test("U16: tất cả ok → healthy, 5 item ok")
    func healthy() async throws {
        let rig = try await Rig.make()
        rig.happyRefresh()
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        #expect(result.status == .healthy)
        #expect(result.checks.count == 5)
        #expect(result.checks.allSatisfy({ $0.ok }))
    }

    @Test("U17: lưu 3 kết quả; audit status_changed đúng 1 lần khi healthy→needsReauth→needsReauth")
    func savesAndAudits() async throws {
        let rig = try await Rig.make()
        rig.happyRefresh()
        _ = try await rig.checker.check(rig.account.id, actor: .scheduler)

        // Stub riêng cho lỗi; checker thứ hai dựng lại dùng chung repo (route đầu thắng
        // nên không ghi đè được trên cùng stub).
        let broken = StubHTTPClient()
        broken.on(
            "POST", "https://example.test/google/token", status: 400,
            json: #"{"error":"invalid_grant"}"#)
        let vault = SecretVault(
            store: rig.store, metadata: rig.metadata, audit: rig.audit,
            clock: rig.clock, ids: SequentialIDGenerator())
        let tokens = TokenProvider(
            providers: rig.registry, clients: rig.clients, accounts: rig.accounts,
            credentials: rig.credentials, secrets: vault, audit: rig.audit,
            tokenEndpoint: TokenEndpointClient(http: broken), clock: rig.clock,
            ids: SequentialIDGenerator())
        let failing = HealthChecker(
            accounts: rig.accounts, credentials: rig.credentials, clients: rig.clients,
            secretExists: { _ in true },
            tokens: tokens, providers: rig.registry, probes: { _ in rig.probe },
            results: rig.results, audit: rig.audit, clock: rig.clock,
            ids: SequentialIDGenerator())
        _ = try await failing.check(rig.account.id, actor: .scheduler)
        _ = try await failing.check(rig.account.id, actor: .scheduler)

        let all = try await rig.results.list(for: rig.account.id, limit: 10)
        #expect(all.count == 3)
        let events = try await rig.audit.query(AuditQuery(actions: [.accountStatusChanged]))
        #expect(events.count == 1)
        #expect(events.first?.result == .success)
    }

    @Test("U18: không item error nào chứa access token")
    func noTokenLeak() async throws {
        let probe = FakeProbe.ok()
        probe.fail(with: .unauthorized)
        let rig = try await Rig.make(probe: probe)
        rig.happyRefresh()
        rig.stub.on(
            "POST", "https://example.test/google/token",
            json: #"{"access_token":"at-SECRET","token_type":"Bearer","expires_in":3600}"#)
        let result = try await rig.checker.check(rig.account.id, actor: .scheduler)
        for item in result.checks {
            #expect(item.error?.contains("at-SECRET") != true)
        }
        #expect(String(describing: result).contains("at-SECRET") == false)
    }

    @Test("Edge: account không tồn tại → throw notFound")
    func missingAccount() async throws {
        let rig = try await Rig.make()
        let ghost = AccountID(rawValue: UUID())
        await #expect(throws: DomainError.notFound("account:\(ghost)")) {
            _ = try await rig.checker.check(ghost, actor: .scheduler)
        }
    }
}

/// Store mà get luôn throw interactionNotAllowed (máy khóa).
final class LockingStore: SecretStore, @unchecked Sendable {
    // NSLock + @unchecked Sendable — ngoại lệ Tests/.
    private let backing: InMemorySecretStore

    init(wrapping backing: InMemorySecretStore) {
        self.backing = backing
    }

    func set(_ data: Data, for ref: KeychainRef, policy: SecretAccessPolicy) async throws {
        try await backing.set(data, for: ref, policy: policy)
    }

    func get(_ ref: KeychainRef, reason: String) async throws -> Data {
        throw SecretStoreError.interactionNotAllowed
    }

    func delete(_ ref: KeychainRef) async throws {
        try await backing.delete(ref)
    }

    func contains(_ ref: KeychainRef) async throws -> Bool {
        try await backing.contains(ref)
    }
}
