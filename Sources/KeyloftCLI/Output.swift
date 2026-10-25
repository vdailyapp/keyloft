import Foundation
import VaultDomain

/// stdout/stderr ghi được trong test.
protocol StandardStreams: AnyObject, Sendable {
    func writeStdout(_ text: String)
    func writeStderr(_ text: String)
}

/// Output mặc định: in ra process thật.
final class ProcessStreams: StandardStreams {
    func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

enum TableFormatter {
    /// ID 8 ký tự đầu cho dễ đọc.
    static func shortID(_ id: AccountID) -> String {
        String(id.description.prefix(8))
    }

    static func accountsTable(_ accounts: [Account]) -> String {
        var rows = ["ID       PROVIDER    EMAIL               STATUS      LAST CHECK"]
        for account in accounts {
            let email = account.email ?? "-"
            let last = account.statusChangedAt.formatted(
                date: .abbreviated, time: .shortened)
            rows.append(
                "\(shortID(account.id))  \(account.providerId.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0))  \(email.padding(toLength: 19, withPad: " ", startingAt: 0))  \(account.status.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0))  \(last)"
            )
        }
        return rows.joined(separator: "\n")
    }

    static func healthTable(_ results: [HealthCheckResult]) -> String {
        var rows = ["ACCOUNT  STATUS       LAYER            DETAIL"]
        for result in results {
            let failed = result.checks.last(where: { !$0.ok })
            let layer = failed?.name.rawValue ?? "-"
            let detail = failed?.error ?? result.checks.last?.warnings.joined(separator: ", ") ?? "ok"
            rows.append(
                "\(shortID(result.accountId))  \(result.status.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0))  \(layer.padding(toLength: 16, withPad: " ", startingAt: 0))  \(detail)"
            )
        }
        return rows.joined(separator: "\n")
    }
}

/// DTO cho `keyloft health --json`.
struct HealthDTO: Encodable {
    struct AccountDTO: Encodable {
        let id: String
        let provider: String
        let email: String?
    }

    struct CheckDTO: Encodable {
        let name: String
        let ok: Bool
        let latencyMs: Int?
        let error: String?
        let warnings: [String]
    }

    let account: AccountDTO
    let status: String
    let checkedAt: String
    let checks: [CheckDTO]

    init(account: Account, result: HealthCheckResult) {
        self.account = AccountDTO(
            id: account.id.description, provider: account.providerId.rawValue, email: account.email)
        self.status = result.status.rawValue
        self.checkedAt = ISO8601DateFormatter().string(from: result.checkedAt)
        self.checks = result.checks.map {
            CheckDTO(
                name: $0.name.rawValue, ok: $0.ok, latencyMs: $0.latencyMs,
                error: $0.error, warnings: $0.warnings)
        }
    }
}

struct AccountDTO: Encodable {
    let id: String
    let provider: String
    let email: String?
    let status: String
}
