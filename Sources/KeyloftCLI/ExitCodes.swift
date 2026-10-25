import Foundation
import VaultDomain

enum KeyloftExitCode: Int32 {
    case ok = 0
    case failure = 1
    case needsReauth = 2
    case needsConsent = 3
    case unreachable = 4
    case usage = 64

    static func from(_ status: AccountStatus) -> KeyloftExitCode {
        switch status {
        case .healthy, .degraded: .ok
        case .needsReauth: .needsReauth
        case .needsConsent: .needsConsent
        case .unreachable: .unreachable
        }
    }

    /// Trạng thái nặng nhất theo `AccountStatus.severity`.
    static func worst(_ statuses: [AccountStatus]) -> KeyloftExitCode {
        guard let worst = statuses.max(by: { $0.severity < $1.severity }) else {
            return .ok
        }
        return from(worst)
    }
}
