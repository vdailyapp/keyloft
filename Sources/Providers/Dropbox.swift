import Foundation
import VaultDomain

extension Provider {
    /// Giá trị tĩnh theo SPEC-007 TECH §2. Scope do App Console quyết định.
    public static let dropbox = Provider(
        id: .dropbox,
        displayName: "Dropbox",
        issuer: "https://www.dropbox.com",
        authURL: URL(string: "https://www.dropbox.com/oauth2/authorize")!,
        tokenURL: URL(string: "https://api.dropboxapi.com/oauth2/token")!,
        revokeURL: URL(string: "https://api.dropboxapi.com/2/auth/token/revoke")!,
        discoveryURL: URL(string: "https://www.dropbox.com/.well-known/openid-configuration")!,
        defaultScopes: [
            "account_info.read", "files.metadata.read", "openid", "email",
        ],
        extraAuthParams: [
            "token_access_type": "offline"
        ],
        quirks: ProviderQuirks(
            rotatesRefreshToken: false,
            needsOfflineParam: true,
            incrementalAuth: .consoleThenRelogin,
            revocation: .dropboxAPI(URL(string: "https://api.dropboxapi.com/2/auth/token/revoke")!),
            issuerIsTenantTemplated: false,
            tokenEndpointAuth: .clientSecretPost,
            authorizationResponseIssSupported: false,
            scopeAliases: [:],
            unechoedScopes: [],
            refreshIncludesScope: false
        )
    )
}
