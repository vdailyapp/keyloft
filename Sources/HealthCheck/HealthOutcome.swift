import Foundation
import Providers
import TokenVault
import VaultDomain

/// Lỗi của một tầng health check (đã làm sạch, không chứa dữ liệu nhạy cảm).
public enum LayerFailure: Sendable, Equatable {
    case noRefreshToken
    case refreshInvalidGrant
    case refreshInvalidClient
    case refreshTransient(String)
    case refreshOther(String)
    case apiInsufficientScope(String?)
    case apiTransient(String)
    case apiRejected(String)
    case missingScopes(ScopeSet)

    /// Tên dùng cho `HealthCheckItem.error` — tên case + tham số dạng chữ, không mô tả thô.
    public var label: String {
        switch self {
        case .noRefreshToken: "noRefreshToken"
        case .refreshInvalidGrant: "refreshInvalidGrant"
        case .refreshInvalidClient: "refreshInvalidClient"
        case .refreshTransient(let detail): "refreshTransient(\(detail))"
        case .refreshOther(let detail): "refreshOther(\(detail))"
        case .apiInsufficientScope(let scope): "apiInsufficientScope(\(scope ?? ""))"
        case .apiTransient(let detail): "apiTransient(\(detail))"
        case .apiRejected(let detail): "apiRejected(\(detail))"
        case .missingScopes(let scopes): "missingScopes(\(scopes.spaceDelimited))"
        }
    }
}

/// Thuần: tầng lỗi đầu tiên (nếu có) + cảnh báo → trạng thái account.
public func status(for failure: LayerFailure?, warnings: [String]) -> AccountStatus {
    switch failure {
    case .noRefreshToken, .refreshInvalidGrant:
        return .needsReauth
    case .refreshInvalidClient, .refreshOther, .apiRejected:
        return .degraded
    case .refreshTransient, .apiTransient:
        return .unreachable
    case .apiInsufficientScope, .missingScopes:
        return .needsConsent
    case nil:
        return warnings.isEmpty ? .healthy : .degraded
    }
}

/// Map lỗi TokenProvider (tầng refresh) → LayerFailure.
func layerFailure(for error: TokenVaultError) -> LayerFailure {
    switch error {
    case .noActiveCredential, .accountNotFound:
        return .noRefreshToken
    case .oauth(let oauth):
        switch oauth {
        case .invalidGrant: return .refreshInvalidGrant
        case .invalidClient: return .refreshInvalidClient
        case let oauthError where oauthError.isTransient:
            return .refreshTransient("\(oauthError.kind)")
        default: return .refreshOther("\(oauth.kind)")
        }
    case .rotationPersistFailed:
        return .refreshInvalidGrant
    case .secret:
        // Keychain chưa đọc được (vd máy khóa) — token vẫn còn, không phải needsReauth.
        return .refreshTransient("secretUnavailable")
    }
}

/// Map lỗi probe (tầng apiCall) → LayerFailure.
func layerFailure(for error: ProbeError) -> LayerFailure {
    switch error {
    case .insufficientScope(let scope): return .apiInsufficientScope(scope)
    case .unauthorized, .forbidden, .malformed: return .apiRejected("\(error.kind)")
    case let probeError where probeError.isTransient:
        return .apiTransient("\(probeError.kind)")
    default:
        return .apiRejected("\(error.kind)")
    }
}

extension OAuthError {
    var kind: String {
        switch self {
        case .invalidGrant: "invalidGrant"
        case .invalidClient: "invalidClient"
        case .invalidScope: "invalidScope"
        case .insufficientScope: "insufficientScope"
        case .accessDenied: "accessDenied"
        case .other(let code, _): "other(\(code))"
        case .userCancelled: "userCancelled"
        case .timeout: "timeout"
        case .stateMismatch: "stateMismatch"
        case .issuerMismatch: "issuerMismatch"
        case .accountMismatch: "accountMismatch"
        case .missingRefreshToken: "missingRefreshToken"
        case .missingIDToken: "missingIDToken"
        case .invalidIDToken: "invalidIDToken"
        case .missingCode: "missingCode"
        case .network(let code): "network(\(code.rawValue))"
        case .server(let code): "server(\(code))"
        case .malformedResponse: "malformedResponse"
        case .revocationUnsupported: "revocationUnsupported"
        }
    }
}

extension ProbeError {
    var kind: String {
        switch self {
        case .unauthorized: "unauthorized"
        case .insufficientScope: "insufficientScope"
        case .forbidden: "forbidden"
        case .rateLimited: "rateLimited"
        case .server(let code): "server(\(code))"
        case .network(let code): "network(\(code.rawValue))"
        case .malformed: "malformed"
        }
    }
}
