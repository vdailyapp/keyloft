import Foundation
import VaultDomain

extension Provider {
    /// Giá trị tĩnh theo SPEC-007 TECH §2 (đúng tại 2026-10-25).
    public static let google = Provider(
        id: .google,
        displayName: "Google",
        issuer: "https://accounts.google.com",
        authURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
        revokeURL: URL(string: "https://oauth2.googleapis.com/revoke")!,
        discoveryURL: URL(string: "https://accounts.google.com/.well-known/openid-configuration")!,
        defaultScopes: [
            "openid", "email", "https://www.googleapis.com/auth/drive",
        ],
        extraAuthParams: [
            "access_type": "offline",
            "prompt": "consent",
        ],
        quirks: ProviderQuirks(
            rotatesRefreshToken: false,
            needsOfflineParam: true,
            incrementalAuth: .includeGrantedScopes,
            revocation: .rfc7009(
                URL(string: "https://oauth2.googleapis.com/revoke")!, revokesWholeGrant: true),
            issuerIsTenantTemplated: false,
            tokenEndpointAuth: .clientSecretPost,
            authorizationResponseIssSupported: false,
            scopeAliases: [
                "email": "https://www.googleapis.com/auth/userinfo.email",
                "profile": "https://www.googleapis.com/auth/userinfo.profile",
            ],
            unechoedScopes: [],
            refreshIncludesScope: false
        )
    )
}
