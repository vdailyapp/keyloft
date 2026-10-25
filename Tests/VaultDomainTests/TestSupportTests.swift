import Foundation
import KeyloftTestSupport
import Testing
import VaultDomain

@Suite("KeyloftTestSupport fakes")
struct TestSupportTests {
    @Test("U12: StubHTTPClient không khớp route → URLError(.unsupportedURL), requests được ghi")
    func stubNoRoute() async throws {
        let stub = StubHTTPClient()
        stub.on("POST", "https://example.test/token", json: #"{"ok":true}"#)

        var okRequest = URLRequest(url: URL(string: "https://example.test/token?x=1")!)
        okRequest.httpMethod = "POST"
        let ok = try await stub.send(okRequest)
        #expect(ok.1.statusCode == 200)

        do {
            _ = try await stub.send(URLRequest(url: URL(string: "https://other.test/nope")!))
            Issue.record("phải throw URLError khi không khớp route")
        } catch let error as URLError {
            #expect(error.code == .unsupportedURL)
        }
        #expect(stub.requests.count == 2)
    }

    @Test("U12: InMemoryHealthCheckRepository.append 51 lần → giữ 50 mới nhất")
    func healthRetention() async throws {
        let db = InMemoryDatabase()
        let repo = InMemoryHealthCheckRepository(db: db)
        let account = TestData.account()
        try await InMemoryAccountRepository(db: db).save(account)

        let clock = FixedDateProvider()
        let ids = SequentialIDGenerator()
        for _ in 0...50 {
            try await repo.append(
                HealthCheckResult(
                    id: HealthCheckID(rawValue: ids.make()),
                    accountId: account.id,
                    checkedAt: clock.now(),
                    status: .healthy,
                    checks: []))
            clock.advance(by: 60)
        }

        let all = try await repo.list(for: account.id, limit: 100)
        #expect(all.count == HealthCheckRetention.perAccount)
        let latest = try await repo.latest(for: account.id)
        #expect(latest?.checkedAt == all.first?.checkedAt)
        // Bản cũ nhất bị xóa là bản đầu tiên (epoch), không còn trong list.
        #expect(all.allSatisfy { $0.checkedAt > TestData.epoch })
    }

    @Test("InMemory: xóa account cascade credential + health result")
    func cascadeDelete() async throws {
        let db = InMemoryDatabase()
        let accounts = InMemoryAccountRepository(db: db)
        let credentials = InMemoryCredentialRepository(db: db)
        let health = InMemoryHealthCheckRepository(db: db)
        let account = TestData.account()
        try await accounts.save(account)
        try await credentials.insert(TestData.credential(accountId: account.id))
        try await health.append(
            HealthCheckResult(
                id: HealthCheckID(rawValue: UUID()), accountId: account.id,
                checkedAt: TestData.epoch, status: .healthy, checks: []))

        try await accounts.delete(account.id)
        #expect(try await credentials.list(for: account.id).isEmpty)
        #expect(try await health.list(for: account.id, limit: 10).isEmpty)
    }

    @Test("InMemory: xóa oauth_client còn account → hasDependents; xóa secret còn credential → hasDependents")
    func hasDependents() async throws {
        let db = InMemoryDatabase()
        let clients = InMemoryOAuthClientRepository(db: db)
        let accounts = InMemoryAccountRepository(db: db)
        let secrets = InMemorySecretMetadataRepository(db: db)
        let credentials = InMemoryCredentialRepository(db: db)

        let client = TestData.oauthClient()
        try await clients.save(client)
        try await accounts.save(TestData.account(clientId: client.id))
        await #expect(throws: DomainError.hasDependents("oauth_client:\(client.id)")) {
            try await clients.delete(client.id)
        }

        try await secrets.insert(TestData.secret())
        try await credentials.insert(TestData.credential())
        let secretId = try await secrets.list(kind: .refreshToken).first!.id
        await #expect(throws: DomainError.self) {
            try await secrets.delete(secretId)
        }
    }

    @Test("SequentialIDGenerator tăng dần; SeededRandomSource tất định theo seed")
    func deterministicFakes() throws {
        let ids = SequentialIDGenerator()
        let a = ids.make()
        let b = ids.make()
        #expect(
            a.uuidString == "00000000-0000-0000-0000-000000000001"
                && b.uuidString == "00000000-0000-0000-0000-000000000002")

        let r1 = SeededRandomSource(seed: 42)
        let r2 = SeededRandomSource(seed: 42)
        #expect(try r1.bytes(count: 32) == r2.bytes(count: 32))
        #expect(try r1.bytes(count: 32).count == 32)
    }
}
