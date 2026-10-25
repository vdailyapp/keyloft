import Foundation
import KeyloftTestSupport
import Testing
import VaultDomain

@testable import VaultPersistence

@Suite("Health & audit repositories")
struct HealthAuditRepositoryTests {
    struct Rig {
        let db: VaultDatabase
        let health: GRDBHealthCheckRepository
        let audit: GRDBAuditLog
        let accountA: Account
        let accountB: Account

        static func make() async throws -> Rig {
            let db = try VaultDatabase.inMemory()
            let clients = GRDBOAuthClientRepository(db: db)
            let accounts = GRDBAccountRepository(db: db)
            let client = TestData.oauthClient(hasSecret: false)
            try await clients.save(client)
            let a = TestData.account(id: AccountID(rawValue: UUID()), clientId: client.id, externalId: "a")
            let b = TestData.account(id: AccountID(rawValue: UUID()), clientId: client.id, externalId: "b")
            try await accounts.save(a)
            try await accounts.save(b)
            return Rig(
                db: db, health: GRDBHealthCheckRepository(db: db), audit: GRDBAuditLog(db: db),
                accountA: a, accountB: b)
        }
    }

    @Test("U10: 60 append cho A, 3 cho B → A còn 50 mới nhất, B còn 3")
    func retention() async throws {
        let rig = try await Rig.make()
        let base = Date(timeIntervalSince1970: 10_000)
        for i in 0..<60 {
            try await rig.health.append(
                HealthCheckResult(
                    id: HealthCheckID(rawValue: UUID()), accountId: rig.accountA.id,
                    checkedAt: base.addingTimeInterval(Double(i)), status: .healthy, checks: []))
        }
        for i in 0..<3 {
            try await rig.health.append(
                HealthCheckResult(
                    id: HealthCheckID(rawValue: UUID()), accountId: rig.accountB.id,
                    checkedAt: base.addingTimeInterval(Double(i)), status: .degraded, checks: []))
        }

        let forA = try await rig.health.list(for: rig.accountA.id, limit: 100)
        #expect(forA.count == 50)
        // 50 bản mới nhất = checkedAt từ +10 đến +59 (bỏ +0...+9).
        #expect(forA.last?.checkedAt == base.addingTimeInterval(10))
        #expect(forA.first?.checkedAt == base.addingTimeInterval(59))
        #expect(try await rig.health.list(for: rig.accountB.id, limit: 100).count == 3)
    }

    @Test("U11: latest mới nhất trước; limit được tôn trọng")
    func latestAndLimit() async throws {
        let rig = try await Rig.make()
        let base = Date(timeIntervalSince1970: 5_000)
        for i in 0..<5 {
            try await rig.health.append(
                HealthCheckResult(
                    id: HealthCheckID(rawValue: UUID()), accountId: rig.accountA.id,
                    checkedAt: base.addingTimeInterval(Double(i)), status: .healthy, checks: []))
        }
        let latest = try await rig.health.latest(for: rig.accountA.id)
        #expect(latest?.checkedAt == base.addingTimeInterval(4))
        let first3 = try await rig.health.list(for: rig.accountA.id, limit: 3)
        #expect(first3.map(\.checkedAt) == (2...4).reversed().map { base.addingTimeInterval(Double($0)) })
    }

    @Test("U12: audit query lọc target/actions/since/limit, mới nhất trước")
    func auditQuery() async throws {
        let rig = try await Rig.make()
        let base = Date(timeIntervalSince1970: 100)
        let ids = SequentialIDGenerator()
        func event(_ action: AuditAction, target: String, at: Double) -> AuditEvent {
            AuditEvent(
                id: AuditEventID(rawValue: ids.make()), actor: .user, action: action,
                target: target, result: .success, timestamp: base.addingTimeInterval(at))
        }
        // 10 event lẫn target/action/thời gian.
        for i in 0..<10 {
            let target = i % 2 == 0 ? "account:a" : "credential:c"
            let action: AuditAction = i % 3 == 0 ? .tokenRefreshed : .scopeGranted
            try await rig.audit.append(event(action, target: target, at: Double(i)))
        }

        let byTarget = try await rig.audit.query(AuditQuery(target: "account:a"))
        #expect(byTarget.count == 5)
        #expect(byTarget.allSatisfy { $0.target == "account:a" })

        let byAction = try await rig.audit.query(AuditQuery(actions: [.tokenRefreshed]))
        #expect(byAction.count == 4)

        let since = try await rig.audit.query(AuditQuery(since: base.addingTimeInterval(7)))
        #expect(since.count == 3)

        let combined = try await rig.audit.query(
            AuditQuery(target: "credential:c", actions: [.scopeGranted], limit: 2))
        #expect(combined.count == 2)

        // Mới nhất trước.
        let all = try await rig.audit.query(AuditQuery())
        #expect(all.first!.timestamp >= all.last!.timestamp)
    }
}
