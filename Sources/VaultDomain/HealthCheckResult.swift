import Foundation

public enum HealthLayer: String, Codable, Sendable, CaseIterable {
    case tokenPresent, refresh, apiCall, scopes, earlyWarning
}

public struct HealthCheckItem: Codable, Sendable, Equatable {
    public var name: HealthLayer
    public var ok: Bool
    public var latencyMs: Int?
    /// Thông điệp đã làm sạch, không chứa token.
    public var error: String?
    /// Chỉ dùng ở earlyWarning: "quota>90%", "clientSecret<30d", "slow".
    public var warnings: [String]

    public init(
        name: HealthLayer,
        ok: Bool,
        latencyMs: Int? = nil,
        error: String? = nil,
        warnings: [String] = []
    ) {
        self.name = name
        self.ok = ok
        self.latencyMs = latencyMs
        self.error = error
        self.warnings = warnings
    }
}

public struct HealthCheckResult: Codable, Sendable, Equatable, Identifiable {
    public let id: HealthCheckID
    public var accountId: AccountID
    public var checkedAt: Date
    public var status: AccountStatus
    public var checks: [HealthCheckItem]

    public init(
        id: HealthCheckID,
        accountId: AccountID,
        checkedAt: Date,
        status: AccountStatus,
        checks: [HealthCheckItem]
    ) {
        self.id = id
        self.accountId = accountId
        self.checkedAt = checkedAt
        self.status = status
        self.checks = checks
    }
}
