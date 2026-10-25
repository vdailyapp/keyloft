import Foundation

public enum OAuthError: Error, Sendable, Equatable {
    // Lỗi từ provider (RFC 6749 §5.2).
    case invalidGrant(String?)
    case invalidClient(String?)
    case invalidScope(String?)
    case insufficientScope(String?)
    case accessDenied(String?)
    case other(code: String, description: String?)

    // Lỗi luồng.
    case userCancelled
    case timeout
    case stateMismatch
    case issuerMismatch(expected: String, actual: String?)
    case accountMismatch(expectedExternalId: String, actualEmail: String?)
    case missingRefreshToken
    case missingIDToken
    case invalidIDToken(String)
    case missingCode

    // Hạ tầng.
    case network(URLError.Code)
    case server(status: Int)
    case malformedResponse(String)
    case revocationUnsupported

    /// true → lỗi tạm thời, KHÔNG được chuyển account sang needsReauth (AGENTS.md).
    public var isTransient: Bool {
        switch self {
        case .network, .server: true
        default: false
        }
    }
}
