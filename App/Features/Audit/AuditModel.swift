import Foundation
import Observation
import VaultDomain
import VaultRuntime

/// Model màn Audit: bảng event mới nhất trước, lọc theo account, action, khoảng thời gian.
@MainActor
@Observable
final class AuditModel {
    /// "Khoảng thời gian" của bộ lọc.
    enum TimeRange: String, CaseIterable {
        case all = "Tất cả"
        case lastHour = "1 giờ"
        case last24h = "24 giờ"
        case last7d = "7 ngày"

        var seconds: TimeInterval? {
            switch self {
            case .all: nil
            case .lastHour: 3600
            case .last24h: 24 * 3600
            case .last7d: 7 * 24 * 3600
            }
        }
    }

    private(set) var rows: [AuditEvent] = []
    private(set) var accounts: [Account] = []
    private(set) var error: String?
    var filterAction: AuditAction?
    var filterAccount: AccountID?
    var filterRange: TimeRange = .all

    private let runtime: VaultRuntime

    init(runtime: VaultRuntime) {
        self.runtime = runtime
    }

    func load() async {
        error = nil
        do {
            accounts = try await runtime.accounts.list()
            let since = filterRange.seconds.map {
                runtime.clock.now().addingTimeInterval(-$0)
            }
            rows = try await runtime.audit.query(
                AuditQuery(
                    target: filterAccount.map { "account:\($0)" },
                    actions: filterAction.map { [$0] },
                    since: since))
        } catch {
            self.error = "\(error)"
        }
    }
}
