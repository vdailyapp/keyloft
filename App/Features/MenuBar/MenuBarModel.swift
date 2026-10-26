import Foundation
import TokenVault
import VaultDomain

/// Màu chấm menu bar theo trạng thái nặng nhất.
enum MenuBarBadge: Equatable {
    case none
    case yellow
    case gray
    case orange
    case red

    static func from(_ statuses: [AccountStatus]) -> MenuBarBadge {
        let worst = statuses.max { $0.severity < $1.severity }
        switch worst {
        case .needsReauth: return .red
        case .needsConsent: return .orange
        case .unreachable: return .gray
        case .degraded: return .yellow
        case .healthy, nil: return .none
        }
    }

    var systemImage: String {
        switch self {
        case .none: "key.horizontal"
        case .yellow: "key.horizontal.fill"
        case .gray: "key.horizontal"
        case .orange: "exclamationmark.key.fill"
        case .red: "xmark.key.fill"
        }
    }
}

/// Hành động chính cho account (menu bar + notification + chi tiết).
enum PrimaryAction: Equatable {
    case none
    case reauth
    case grantMore(GrantMorePlan)
    case retry
    case fixClient(OAuthClientID)
    case openDetails
}

func primaryAction(
    for account: Account, latest: HealthCheckResult?, plan: GrantMorePlan? = nil
) -> PrimaryAction {
    switch account.status {
    case .needsReauth:
        return .reauth
    case .needsConsent:
        return plan.map { .grantMore($0) } ?? .grantMore(.nothingMissing)
    case .unreachable:
        return .retry
    case .degraded:
        // degraded do secret sắp hết hạn → mở form sửa client.
        if latest?.checks.last(where: { !$0.warnings.isEmpty })?.warnings
            .contains(where: { $0.hasPrefix("clientSecret") }) == true
        {
            return .fixClient(account.oauthClientId)
        }
        return .openDetails
    case .healthy:
        return .none
    }
}
