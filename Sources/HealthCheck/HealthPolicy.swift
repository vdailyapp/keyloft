import Foundation

/// Ngưỡng cảnh báo của health check (SPEC-008 §2).
public struct HealthPolicy: Sendable, Equatable {
    public var quotaWarnRatio: Double = 0.9
    public var secretExpiryWarn: TimeInterval = 30 * 86_400
    public var slowThresholdMs: Int = 3_000
    public var freshnessForHeavyTask: TimeInterval = 15 * 60

    public init(
        quotaWarnRatio: Double = 0.9,
        secretExpiryWarn: TimeInterval = 30 * 86_400,
        slowThresholdMs: Int = 3_000,
        freshnessForHeavyTask: TimeInterval = 15 * 60
    ) {
        self.quotaWarnRatio = quotaWarnRatio
        self.secretExpiryWarn = secretExpiryWarn
        self.slowThresholdMs = slowThresholdMs
        self.freshnessForHeavyTask = freshnessForHeavyTask
    }
}
