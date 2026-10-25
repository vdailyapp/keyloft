import Foundation

/// Access token — CHỈ sống trong RAM, không Codable để không vô tình persist.
public struct AccessToken: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let value: String
    public let scopes: ScopeSet
    public let expiresAt: Date

    public init(value: String, scopes: ScopeSet, expiresAt: Date) {
        self.value = value
        self.scopes = scopes
        self.expiresAt = expiresAt
    }

    public func isValid(at now: Date, minValidity: TimeInterval) -> Bool {
        expiresAt.timeIntervalSince(now) > minValidity
    }

    public var description: String { "AccessToken(<redacted>, expiresAt: \(expiresAt))" }
    public var debugDescription: String { description }
}
