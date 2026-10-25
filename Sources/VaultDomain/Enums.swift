import Foundation

public enum VaultDomain {
    public static let version = "0.1.0"
}

public enum ProviderID: String, Codable, Sendable, CaseIterable {
    case google, microsoft, dropbox
}

public enum AccountStatus: String, Codable, Sendable, CaseIterable {
    case healthy, degraded, needsConsent, needsReauth, unreachable

    /// Mức nghiêm trọng để chọn badge menu bar:
    /// needsReauth > needsConsent > unreachable > degraded > healthy.
    public var severity: Int {
        switch self {
        case .healthy: 0
        case .degraded: 1
        case .unreachable: 2
        case .needsConsent: 3
        case .needsReauth: 4
        }
    }
}

public enum CredentialStatus: String, Codable, Sendable {
    case active, superseded, revoked
}

public enum SecretKind: String, Codable, Sendable, CaseIterable {
    case apiKey, password, clientSecret, refreshToken
}
