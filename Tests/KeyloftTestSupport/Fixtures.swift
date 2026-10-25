import Foundation
import VaultDomain

/// Dữ liệu giả dùng chung cho mọi test. URL `https://example.test/...` để không bao giờ
/// trúng endpoint thật.
public enum TestData {
    public static let epoch = Date(timeIntervalSince1970: 1_761_353_600)

    public static let googleQuirks = ProviderQuirks(
        rotatesRefreshToken: false,
        needsOfflineParam: true,
        incrementalAuth: .includeGrantedScopes,
        revocation: .rfc7009(URL(string: "https://example.test/google/revoke")!, revokesWholeGrant: true),
        issuerIsTenantTemplated: false,
        tokenEndpointAuth: .clientSecretPost,
        authorizationResponseIssSupported: false,
        scopeAliases: ["email": "https://www.googleapis.com/auth/userinfo.email"],
        unechoedScopes: [],
        refreshIncludesScope: false
    )

    public static let microsoftQuirks = ProviderQuirks(
        rotatesRefreshToken: true,
        needsOfflineParam: true,
        incrementalAuth: .reauthorize,
        revocation: .unsupported,
        issuerIsTenantTemplated: true,
        tokenEndpointAuth: .clientSecretPost,
        authorizationResponseIssSupported: true,
        scopeAliases: [:],
        unechoedScopes: ["offline_access"],
        refreshIncludesScope: true
    )

    public static let dropboxQuirks = ProviderQuirks(
        rotatesRefreshToken: false,
        needsOfflineParam: true,
        incrementalAuth: .consoleThenRelogin,
        revocation: .dropboxAPI(URL(string: "https://example.test/dropbox/revoke")!),
        issuerIsTenantTemplated: false,
        tokenEndpointAuth: .none,
        authorizationResponseIssSupported: false,
        scopeAliases: [:],
        unechoedScopes: [],
        refreshIncludesScope: false
    )

    public static let googleProvider = Provider(
        id: .google,
        displayName: "Google (test)",
        issuer: "https://accounts.google.com",
        authURL: URL(string: "https://example.test/google/auth")!,
        tokenURL: URL(string: "https://example.test/google/token")!,
        revokeURL: URL(string: "https://example.test/google/revoke")!,
        discoveryURL: URL(string: "https://example.test/google/.well-known/openid-configuration")!,
        defaultScopes: ["openid", "email", "drive"],
        extraAuthParams: ["access_type": "offline", "prompt": "consent"],
        quirks: googleQuirks
    )

    public static let microsoftProvider = Provider(
        id: .microsoft,
        displayName: "Microsoft (test)",
        issuer: "https://login.microsoftonline.com/{tenantid}/v2.0",
        authURL: URL(string: "https://example.test/microsoft/auth")!,
        tokenURL: URL(string: "https://example.test/microsoft/token")!,
        revokeURL: nil,
        discoveryURL: URL(string: "https://example.test/microsoft/.well-known/openid-configuration")!,
        defaultScopes: ["openid", "email", "offline_access", "Files.ReadWrite"],
        extraAuthParams: ["prompt": "select_account"],
        quirks: microsoftQuirks
    )

    public static let dropboxProvider = Provider(
        id: .dropbox,
        displayName: "Dropbox (test)",
        issuer: "https://www.dropboxapi.com/2/oauth2",
        authURL: URL(string: "https://example.test/dropbox/auth")!,
        tokenURL: URL(string: "https://example.test/dropbox/token")!,
        revokeURL: URL(string: "https://example.test/dropbox/revoke")!,
        discoveryURL: nil,
        defaultScopes: ["account_info.read", "files.metadata.read", "openid", "email"],
        extraAuthParams: ["token_access_type": "offline"],
        quirks: dropboxQuirks
    )

    public static var allProviders: [Provider] { [googleProvider, microsoftProvider, dropboxProvider] }

    public static func oauthClient(
        provider: ProviderID = .google,
        id: OAuthClientID = OAuthClientID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!),
        clientId: String = "test-client-id.apps.googleusercontent.com",
        hasSecret: Bool = true,
        createdAt: Date = epoch
    ) -> OAuthClient {
        OAuthClient(
            id: id,
            providerId: provider,
            clientId: clientId,
            clientSecretRef: hasSecret
                ? SecretID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!) : nil,
            redirectURI: URL(string: "http://127.0.0.1/callback")!,
            label: "Test client",
            createdAt: createdAt
        )
    }

    public static func account(
        provider: ProviderID = .google,
        id: AccountID = AccountID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!),
        clientId: OAuthClientID = OAuthClientID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!),
        externalId: String = "test-sub-123",
        email: String? = "user@example.test",
        status: AccountStatus = .healthy,
        createdAt: Date = epoch
    ) -> Account {
        Account(
            id: id,
            providerId: provider,
            oauthClientId: clientId,
            externalId: externalId,
            email: email,
            displayName: "Test User",
            status: status,
            statusChangedAt: createdAt,
            createdAt: createdAt
        )
    }

    public static func credential(
        id: CredentialID = CredentialID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!),
        accountId: AccountID = AccountID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!),
        refreshTokenRef: SecretID = SecretID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!),
        requested: ScopeSet = ["openid", "email", "drive"],
        granted: ScopeSet = ["openid", "email"],
        issuedAt: Date = epoch,
        status: CredentialStatus = .active
    ) -> Credential {
        Credential(
            id: id,
            accountId: accountId,
            refreshTokenRef: refreshTokenRef,
            requestedScopes: requested,
            grantedScopes: granted,
            issuedAt: issuedAt,
            status: status
        )
    }

    public static func secret(
        id: SecretID = SecretID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!),
        kind: SecretKind = .refreshToken,
        label: String = "refresh token",
        requiresUserPresence: Bool = false,
        createdAt: Date = epoch
    ) -> Secret {
        Secret(
            id: id,
            kind: kind,
            label: label,
            keychainRef: KeychainRef(kind: kind, id: id),
            requiresUserPresence: requiresUserPresence,
            createdAt: createdAt
        )
    }
}
