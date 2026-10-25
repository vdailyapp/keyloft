import Foundation
import HealthCheck
import KeyloftTestSupport
import Providers
import SecretVault
import Testing
import TokenVault
import VaultDomain

actor ProbeBox {
    var failure: ProbeError?
    var delay: Duration = .zero
    private(set) var calls = 0
    private var inFlight = 0
    private(set) var maxInFlight = 0

    func set(failure: ProbeError?) {
        self.failure = failure
    }

    func set(delay: Duration) {
        self.delay = delay
    }

    func probe() async throws -> ProbeResult {
        calls += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        let currentFailure = failure
        let currentDelay = delay
        if currentDelay > .zero {
            try await Task.sleep(for: currentDelay)
        }
        inFlight -= 1
        if let currentFailure {
            throw currentFailure
        }
        return ProbeResult(email: nil, quota: nil, latencyMs: 10)
    }
}

/// Probe điều khiển qua ProbeBox (đếm đồng thời, trễ, lỗi).
struct BoxProbe: APIProbe {
    let box: ProbeBox

    func probe(accessToken: String) async throws -> ProbeResult {
        try await box.probe()
    }
}

@Suite("HealthScheduler")
struct HealthSchedulerTests {
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
        let vault: SecretVault
        let probeBox: ProbeBox
        let checker: HealthChecker
        let sleeper: ManualSleeper
        let scheduler: HealthScheduler
        let client: OAuthClient
        let account: Account
        let credential: Credential

        static func make(accountCount: Int = 1) async throws -> Rig {
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
            let ids = SequentialIDGenerator()

            let client = TestData.oauthClient(hasSecret: false)
            try await clients.save(client)

            let granted: ScopeSet = [
                "openid", "https://www.googleapis.com/auth/userinfo.email", "drive",
            ]
            var firstAccount = Account(
                id: AccountID(rawValue: UUID()), providerId: .google, oauthClientId: client.id,
                externalId: "sub-0", email: "a@example.test", displayName: nil,
                status: .healthy, statusChangedAt: clock.now(), createdAt: clock.now())
            for index in 0..<max(1, accountCount) {
                let account =
                    index == 0
                    ? firstAccount
                    : Account(
                        id: AccountID(rawValue: UUID()), providerId: .google,
                        oauthClientId: client.id, externalId: "sub-\(index)",
                        email: "a\(index)@example.test", displayName: nil, status: .healthy,
                        statusChangedAt: clock.now(), createdAt: clock.now())
                try await accounts.save(account)
                let secret = TestData.secret(id: SecretID(rawValue: ids.make()))
                try await metadata.insert(secret)
                try await store.set(
                    Data("rt-\(index)".utf8), for: secret.keychainRef, policy: .afterFirstUnlock)
                try await credentials.insert(
                    TestData.credential(
                        id: CredentialID(rawValue: ids.make()), accountId: account.id,
                        refreshTokenRef: secret.id, granted: granted))
                if index == 0 { firstAccount = account }
            }
            let account = firstAccount

            let vault = SecretVault(
                store: store, metadata: metadata, audit: audit, clock: clock, ids: ids)
            let stub = StubHTTPClient()
            stub.on(
                "POST", "https://example.test/google/token",
                json: #"{"access_token":"at-1","token_type":"Bearer","expires_in":3600}"#)
            let tokens = TokenProvider(
                providers: registry, clients: clients, accounts: accounts,
                credentials: credentials, secrets: vault, audit: audit,
                tokenEndpoint: TokenEndpointClient(http: stub), clock: clock, ids: ids)
            let probeBox = ProbeBox()
            let checker = HealthChecker(
                accounts: accounts, credentials: credentials, clients: clients,
                secretExists: { id in
                    guard let secret = try await metadata.get(id) else { return false }
                    return try await store.contains(secret.keychainRef)
                },
                tokens: tokens, providers: registry,
                probes: { _ in BoxProbe(box: probeBox) },
                results: results, audit: audit, clock: clock, ids: ids)
            let sleeper = ManualSleeper()
            let scheduler = HealthScheduler(
                checker: checker, accounts: accounts, results: results, clock: clock,
                sleeper: sleeper, interval: 6 * 3600, maxConcurrent: 3)

            let credential = try await credentials.active(for: account.id)!
            return Rig(
                db: db, store: store, audit: audit, clock: clock, stub: stub,
                registry: registry, clients: clients, accounts: accounts,
                credentials: credentials, metadata: metadata, results: results,
                vault: vault, probeBox: probeBox, checker: checker, sleeper: sleeper,
                scheduler: scheduler, client: client, account: account, credential: credential)
        }
    }

    @Test("U19: dedupe — 2 run(.manual(A)) đồng thời → probe 1 lần, kết quả bằng nhau")
    func dedupe() async throws {
        let rig = try await Rig.make()
        await rig.probeBox.set(delay: .milliseconds(80))

        async let first: [HealthCheckResult] = rig.scheduler.run(.manual(rig.account.id))
        async let second: [HealthCheckResult] = rig.scheduler.run(.manual(rig.account.id))
        let (a, b) = try await (first, second)
        #expect(a.count == 1)
        #expect(b.count == 1)
        #expect(a[0].id == b[0].id)
        let calls = await rig.probeBox.calls
        #expect(calls == 1)
    }

    @Test("U20: 10 account, probe trễ — đồng thời tối đa == 3")
    func concurrencyLimit() async throws {
        let rig = try await Rig.make(accountCount: 10)
        await rig.probeBox.set(delay: .milliseconds(60))

        let results = await rig.scheduler.run(.periodic)
        #expect(results.count == 10)
        let maxConcurrent = await rig.probeBox.maxInFlight
        #expect(maxConcurrent == 3)
    }

    @Test("U21: backoff unreachable liên tục — 60,120,240,480,960,1800,1800")
    func backoffSequence() async throws {
        let rig = try await Rig.make()
        await rig.probeBox.set(failure: .rateLimited)

        _ = await rig.scheduler.run(.manual(rig.account.id))  // check 1 → sleep 60
        let delays = [60.0, 120, 240, 480, 960, 1800, 1800]
        for totalChecks in 2...7 {
            await rig.sleeper.advance(by: 3600)  // đủ để retry tới hạn chạy
            while await rig.probeBox.calls < totalChecks {
                try await Task.sleep(for: .milliseconds(2))
            }
            // Check xong mới lên lịch sleep kế tiếp.
            while await rig.sleeper.requested.count < totalChecks {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        let requested = await rig.sleeper.requested
        #expect(Array(requested.prefix(7)) == delays)
    }

    @Test("U22: backoff reset — unreachable 2 lần rồi healthy → retry dừng, bắt đầu lại từ 60")
    func backoffReset() async throws {
        let rig = try await Rig.make()
        await rig.probeBox.set(failure: .network(.timedOut))

        _ = await rig.scheduler.run(.manual(rig.account.id))  // unreachable → sleep 60
        await rig.sleeper.advance(by: 60)
        while await rig.probeBox.calls < 2 {
            try await Task.sleep(for: .milliseconds(2))
        }
        // Lần 2 unreachable → sleep 120; giờ hết lỗi → check tiếp healthy → reset.
        await rig.probeBox.set(failure: nil)
        await rig.sleeper.advance(by: 120)
        while await rig.probeBox.calls < 3 {
            try await Task.sleep(for: .milliseconds(2))
        }
        try await Task.sleep(for: .milliseconds(20))

        // Healthy → không còn sleep mới ngoài 60, 120 đã dùng.
        var requested = await rig.sleeper.requested
        #expect(requested == [60, 120])

        // Unreachable trở lại → bắt đầu lại từ 60.
        await rig.probeBox.set(failure: .rateLimited)
        _ = await rig.scheduler.run(.manual(rig.account.id))
        requested = await rig.sleeper.requested
        #expect(requested.last == 60)
    }

    @Test("U23: periodic — advance 6h → chạy cho mọi account")
    func periodic() async throws {
        let rig = try await Rig.make(accountCount: 2)
        let (external, continuation) = AsyncStream<HealthTrigger>.makeStream()
        await rig.scheduler.start(external: external)

        // Chờ vòng định kỳ đăng ký sleep TRƯỚC khi tiến thời gian (tránh race chạy trước Task).
        while await rig.sleeper.requested.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        await rig.sleeper.advance(by: 6 * 3600)
        while await rig.probeBox.calls < 2 {
            try await Task.sleep(for: .milliseconds(2))
        }
        let results = try await rig.results.list(for: rig.account.id, limit: 10)
        #expect(results.count == 1)
        continuation.finish()
        await rig.scheduler.stop()
    }

    @Test("U24: external trigger .wake → chạy cho mọi account")
    func wakeTrigger() async throws {
        let rig = try await Rig.make(accountCount: 2)
        let (external, continuation) = AsyncStream<HealthTrigger>.makeStream()
        await rig.scheduler.start(external: external)
        continuation.yield(.wake)

        while await rig.probeBox.calls < 2 {
            try await Task.sleep(for: .milliseconds(2))
        }
        let all = try await rig.results.list(for: rig.account.id, limit: 10)
        #expect(all.count == 1)
        continuation.finish()
        await rig.scheduler.stop()
    }

    @Test("U25: ensureFresh còn mới (healthy 10 phút trước) → không gọi probe")
    func ensureFreshSkips() async throws {
        let rig = try await Rig.make()
        _ = await rig.scheduler.run(.manual(rig.account.id))  // healthy
        rig.clock.advance(by: 10 * 60)  // còn新鲜 < 15 phút
        let before = await rig.probeBox.calls

        let result = try await rig.scheduler.ensureFresh(rig.account.id)
        #expect(result.status == .healthy)
        let after = await rig.probeBox.calls
        #expect(after == before)
    }

    @Test("U26: ensureFresh cũ / needsConsent → check mới")
    func ensureFreshRuns() async throws {
        let rig = try await Rig.make()
        _ = await rig.scheduler.run(.manual(rig.account.id))
        rig.clock.advance(by: 20 * 60)  // cũ hơn freshness
        _ = try await rig.scheduler.ensureFresh(rig.account.id)
        let calls = await rig.probeBox.calls
        #expect(calls == 2)
        rig.clock.advance(by: 20 * 60)  // kết quả ensureFresh cũng cũ cho bước dưới

        // Kết quả needsConsent mới vẫn phải check lại.
        await rig.probeBox.set(failure: .insufficientScope("drive"))
        _ = try await rig.scheduler.run(.manual(rig.account.id))
        let before = await rig.probeBox.calls
        _ = try await rig.scheduler.ensureFresh(rig.account.id)
        let after = await rig.probeBox.calls
        #expect(after == before + 1)
    }

    @Test("Edge: stop() hủy periodic + retry — không chạy gì sau stop")
    func stopHaltsEverything() async throws {
        let rig = try await Rig.make()
        await rig.probeBox.set(failure: .rateLimited)
        let (external, continuation) = AsyncStream<HealthTrigger>.makeStream()
        await rig.scheduler.start(external: external)

        _ = await rig.scheduler.run(.manual(rig.account.id))  // lên lịch retry 60s
        await rig.scheduler.stop()
        let callsBefore = await rig.probeBox.calls
        await rig.sleeper.advance(by: 10 * 3600)  // kể cả periodic + retry
        try await Task.sleep(for: .milliseconds(30))
        let callsAfter = await rig.probeBox.calls
        #expect(callsAfter == callsBefore)
        continuation.finish()
    }

    @Test("Edge: account bị xóa giữa chừng → bỏ qua, không crash")
    func deletedAccountSkipped() async throws {
        let rig = try await Rig.make()
        try await rig.accounts.delete(rig.account.id)
        let results = await rig.scheduler.run(.manual(rig.account.id))
        #expect(results.isEmpty)
    }
}
