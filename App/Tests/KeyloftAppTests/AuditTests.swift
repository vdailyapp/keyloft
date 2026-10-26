import Foundation
import Testing
import VaultDomain
import VaultRuntime
import KeyloftTestSupport
@testable import Keyloft

@MainActor
@Suite("Audit")
struct AuditTests {
    @Test("U16: lọc action scope.denied → chỉ event đó")
    func filterByAction() async throws {
        let clock = FixedDateProvider()
        let runtime = try await AccountsTests.makeRuntime()
        let client = try await AccountsTests.seedClient(runtime)
        let account = TestData.account(clientId: client.id)
        try await runtime.accounts.save(account)

        var ids: [AuditEventID] = []
        for i in 0..<3 {
            ids.append(AuditEventID(rawValue: UUID()))
        }
        try await runtime.audit.append(
            AuditEvent(
                id: ids[0], actor: .user, action: .scopeGranted,
                target: "account:\(account.id)", scopes: ["drive"], result: .success,
                timestamp: clock.now()))
        try await runtime.audit.append(
            AuditEvent(
                id: ids[1], actor: .user, action: .scopeDenied,
                target: "account:\(account.id)", scopes: ["calendar"], result: .success,
                timestamp: clock.now()))
        try await runtime.audit.append(
            AuditEvent(
                id: ids[2], actor: .scheduler, action: .tokenRefreshed,
                target: "account:\(account.id)", scopes: nil, result: .success,
                timestamp: clock.now()))

        let model = AuditModel(runtime: runtime)
        await model.load()
        #expect(model.rows.count == 3)

        model.filterAction = .scopeDenied
        await model.load()

        #expect(model.rows.count == 1)
        #expect(model.rows[0].action == .scopeDenied)
        #expect(model.rows[0].scopes == ["calendar"])

        // Lọc theo account target cũng hoạt động.
        model.filterAction = nil
        model.filterAccount = account.id
        await model.load()
        #expect(model.rows.count == 3)
    }
}
