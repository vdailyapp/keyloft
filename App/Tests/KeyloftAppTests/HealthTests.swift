import Foundation
import Testing
import VaultDomain
import VaultRuntime
import KeyloftTestSupport
@testable import Keyloft

@MainActor
@Suite("Health history")
struct HealthTests {
    @Test("U15: 3 kết quả — mới nhất trước; tầng hiển thị đúng thứ tự")
    func historyNewestFirstWithLayers() async throws {
        let clock = FixedDateProvider()
        let runtime = try await AccountsTests.makeRuntime()
        let client = try await AccountsTests.seedClient(runtime)
        let account = TestData.account(clientId: client.id)
        try await runtime.accounts.save(account)

        // 3 lần check, lần sau mới hơn; mỗi kết quả 5 tầng đúng thứ tự checker chạy.
        let layers: [HealthCheckItem] = [
            HealthCheckItem(name: .tokenPresent, ok: true),
            HealthCheckItem(name: .refresh, ok: true, latencyMs: 120),
            HealthCheckItem(name: .apiCall, ok: true, latencyMs: 300),
            HealthCheckItem(name: .scopes, ok: true),
            HealthCheckItem(name: .earlyWarning, ok: true, warnings: ["quota>90%"]),
        ]
        for i in 0..<3 {
            try await runtime.healthResults.append(
                HealthCheckResult(
                    id: HealthCheckID(rawValue: UUID()),
                    accountId: account.id,
                    checkedAt: clock.now().addingTimeInterval(Double(i)),
                    status: .healthy,
                    checks: layers))
        }

        let model = HealthHistoryModel(runtime: runtime, accountId: account.id)
        await model.load()

        #expect(model.rows.count == 3)
        // Mới nhất trước.
        #expect(model.rows[0].checkedAt == clock.now().addingTimeInterval(2))
        #expect(model.rows[2].checkedAt == clock.now())
        // Tầng hiển thị đúng thứ tự lưu trong kết quả.
        #expect(
            model.rows[0].checks.map(\.name)
                == [.tokenPresent, .refresh, .apiCall, .scopes, .earlyWarning])
        #expect(model.rows[0].checks[1].latencyMs == 120)
        #expect(model.rows[0].checks[4].warnings == ["quota>90%"])
    }
}
