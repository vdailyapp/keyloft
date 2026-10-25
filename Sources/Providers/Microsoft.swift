import Foundation
import VaultDomain

extension Provider {
    /// Giá trị tĩnh theo SPEC-007 TECH §2. Microsoft xoay vòng refresh token mỗi lần refresh.
    public static let microsoft = Provider(
        id: .microsoft,
        displayName: "Microsoft",
        issuer: "https://login.microsoftonline.com/{tenantid}/v2.0",
        authURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
        tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
        revokeURL: nil,
        discoveryURL: URL(
            string: "https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration")!,
        defaultScopes: [
            "openid", "email", "profile", "offline_access", "User.Read", "Files.ReadWrite",
        ],
        extraAuthParams: [
            "prompt": "select_account"
        ],
        quirks: ProviderQuirks(
            rotatesRefreshToken: true,
            needsOfflineParam: false,
            incrementalAuth: .reauthorize,
            revocation: .unsupported,
            issuerIsTenantTemplated: true,
            tokenEndpointAuth: .clientSecretPost,
            authorizationResponseIssSupported: false,
            scopeAliases: [:],
            unechoedScopes: ["offline_access"],
            refreshIncludesScope: true
        )
    )
}
