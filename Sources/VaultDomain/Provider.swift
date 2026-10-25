import Foundation

public enum IncrementalAuthStyle: String, Codable, Sendable {
    case includeGrantedScopes
    case reauthorize
    case consoleThenRelogin
}

/// Cách thu hồi credential của từng provider (RFC 7009 hoặc API riêng).
public enum RevocationStyle: Codable, Sendable, Equatable {
    /// Google: thu cả grant của client trên account (whole grant = true).
    case rfc7009(URL, revokesWholeGrant: Bool)
    /// Dropbox: POST /2/auth/token/revoke với Bearer access token.
    case dropboxAPI(URL)
    /// Microsoft: không có endpoint thu hồi.
    case unsupported
}

public enum TokenEndpointAuthMethod: String, Codable, Sendable {
    case clientSecretPost
    case clientSecretBasic
    case none
}

/// Hành vi riêng của provider mà luồng OAuth phải xử lý khác nhau.
public struct ProviderQuirks: Codable, Sendable, Equatable {
    public var rotatesRefreshToken: Bool
    public var needsOfflineParam: Bool
    public var incrementalAuth: IncrementalAuthStyle
    public var revocation: RevocationStyle
    /// Microsoft: iss = https://login.microsoftonline.com/{tenantid}/v2.0.
    public var issuerIsTenantTemplated: Bool
    public var tokenEndpointAuth: TokenEndpointAuthMethod
    /// RFC 9207: true → callback BẮT BUỘC có iss.
    public var authorizationResponseIssSupported: Bool
    /// Scope provider trả dạng khác lúc xin (Google: "email" → URL dài).
    public var scopeAliases: [String: String]
    /// Scope không bao giờ được echo lại trong token response (Microsoft: offline_access).
    public var unechoedScopes: ScopeSet
    /// Gửi `scope` (= grantedScopes) khi refresh. Microsoft: true.
    public var refreshIncludesScope: Bool

    public init(
        rotatesRefreshToken: Bool,
        needsOfflineParam: Bool,
        incrementalAuth: IncrementalAuthStyle,
        revocation: RevocationStyle,
        issuerIsTenantTemplated: Bool,
        tokenEndpointAuth: TokenEndpointAuthMethod,
        authorizationResponseIssSupported: Bool,
        scopeAliases: [String: String] = [:],
        unechoedScopes: ScopeSet = [],
        refreshIncludesScope: Bool = false
    ) {
        self.rotatesRefreshToken = rotatesRefreshToken
        self.needsOfflineParam = needsOfflineParam
        self.incrementalAuth = incrementalAuth
        self.revocation = revocation
        self.issuerIsTenantTemplated = issuerIsTenantTemplated
        self.tokenEndpointAuth = tokenEndpointAuth
        self.authorizationResponseIssSupported = authorizationResponseIssSupported
        self.scopeAliases = scopeAliases
        self.unechoedScopes = unechoedScopes
        self.refreshIncludesScope = refreshIncludesScope
    }
}

/// Cấu hình tĩnh provider, nạp trong code (SPEC-007); không Codable.
public struct Provider: Sendable, Equatable, Identifiable {
    public let id: ProviderID
    public let displayName: String
    /// Dùng so khớp iss (RFC 9207) và id_token.iss.
    public let issuer: String
    public let authURL: URL
    public let tokenURL: URL
    public let revokeURL: URL?
    public let discoveryURL: URL?
    /// Cũng là "scope đang cần" ở giai đoạn 1.
    public let defaultScopes: ScopeSet
    public var extraAuthParams: [String: String]
    public let quirks: ProviderQuirks

    public init(
        id: ProviderID,
        displayName: String,
        issuer: String,
        authURL: URL,
        tokenURL: URL,
        revokeURL: URL?,
        discoveryURL: URL?,
        defaultScopes: ScopeSet,
        extraAuthParams: [String: String] = [:],
        quirks: ProviderQuirks
    ) {
        self.id = id
        self.displayName = displayName
        self.issuer = issuer
        self.authURL = authURL
        self.tokenURL = tokenURL
        self.revokeURL = revokeURL
        self.discoveryURL = discoveryURL
        self.defaultScopes = defaultScopes
        self.extraAuthParams = extraAuthParams
        self.quirks = quirks
    }
}
