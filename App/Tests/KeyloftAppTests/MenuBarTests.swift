import Foundation
import Testing
import VaultDomain
import KeyloftTestSupport
@testable import Keyloft

@Suite("Menu bar")
struct MenuBarTests {
    @Test("U1: badge 5 trạng thái + rỗng + hỗn hợp → nặng nhất")
    func badge() {
        #expect(MenuBarBadge.from([.needsReauth]) == .red)
        #expect(MenuBarBadge.from([.needsConsent]) == .orange)
        #expect(MenuBarBadge.from([.unreachable]) == .gray)
        #expect(MenuBarBadge.from([.degraded]) == .yellow)
        #expect(MenuBarBadge.from([.healthy]) == .none)
        #expect(MenuBarBadge.from([]) == .none)
        #expect(MenuBarBadge.from([.healthy, .degraded, .needsReauth]) == .red)
        #expect(MenuBarBadge.from([.needsConsent, .unreachable]) == .orange)
    }

    @Test("U2: primary action theo trạng thái + cảnh báo secret")
    func primaryActions() {
        func account(_ status: AccountStatus) -> Account {
            TestData.account(status: status)
        }
        func result(warnings: [String] = []) -> HealthCheckResult {
            HealthCheckResult(
                id: HealthCheckID(rawValue: UUID()), accountId: AccountID(rawValue: UUID()),
                checkedAt: Date(), status: .degraded,
                checks: [
                    HealthCheckItem(name: .earlyWarning, ok: true, warnings: warnings)
                ])
        }

        #expect(primaryAction(for: account(.needsReauth), latest: nil) == .reauth)
        #expect(
            primaryAction(for: account(.needsConsent), latest: nil)
                == .grantMore(.nothingMissing))
        #expect(primaryAction(for: account(.unreachable), latest: nil) == .retry)
        #expect(primaryAction(for: account(.healthy), latest: nil) == .none)

        let clientId = OAuthClientID(rawValue: UUID())
        let expiring = account(.degraded)
        // OAuthClient không thể đổi oauthClientId sau khi tạo → dựng account với client.
        let degradedAccount = TestData.account(clientId: clientId, status: .degraded)
        #expect(
            primaryAction(for: degradedAccount, latest: result(warnings: ["clientSecret<30d"]))
                == .fixClient(clientId))
        #expect(
            primaryAction(for: degradedAccount, latest: result(warnings: ["quota>90%"]))
                == .openDetails)
        _ = expiring
    }
}
