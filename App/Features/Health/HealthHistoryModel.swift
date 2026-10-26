import Foundation
import Observation
import VaultDomain
import VaultRuntime

/// Lịch sử health check của một account: 50 kết quả gần nhất, mới nhất trước.
@MainActor
@Observable
final class HealthHistoryModel {
    /// Giới hạn hiển thị = retention của repo (SPEC-003).
    static let displayLimit = 50

    private(set) var rows: [HealthCheckResult] = []
    private(set) var error: String?

    let accountId: AccountID
    private let runtime: VaultRuntime

    init(runtime: VaultRuntime, accountId: AccountID) {
        self.runtime = runtime
        self.accountId = accountId
    }

    func load() async {
        error = nil
        do {
            rows = try await runtime.healthResults.list(
                for: accountId, limit: Self.displayLimit)
        } catch {
            self.error = "\(error)"
        }
    }

    /// "Check now" — lỗi scheduler hiện cho người dùng, không nuốt.
    func checkNow() async {
        do {
            _ = try await runtime.scheduler.run(.manual(accountId))
        } catch {
            self.error = "\(error)"
        }
        await load()
    }
}
