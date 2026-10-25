import Foundation
import SecretVault
import VaultDomain

public enum GrantMorePlan: Sendable, Equatable {
    case browser(LoginRequest)
    /// Dropbox: người dùng tick scope trong App Console trước, rồi chạy `then`.
    case consoleThenRelogin(consoleURL: URL, missing: ScopeSet, then: LoginRequest)
    case nothingMissing
}

public enum RevocationOutcome: Sendable, Equatable {
    case revokedRemotely
    /// Provider không hỗ trợ thu hồi / lỗi mạng khi xóa account.
    case localOnly(reason: String)
}

public struct RemovalReport: Sendable, Equatable {
    public var revocations: [CredentialID: RevocationOutcome]
    /// Secret xóa Keychain thất bại — UI cảnh báo còn sót.
    public var leftoverSecrets: [SecretID]

    public init(revocations: [CredentialID: RevocationOutcome], leftoverSecrets: [SecretID]) {
        self.revocations = revocations
        self.leftoverSecrets = leftoverSecrets
    }
}

public enum ScopeServiceError: Error, Sendable, Equatable {
    /// Reduce với scope không có sẵn.
    case notSubset(extra: ScopeSet)
    case grantWideRevocationNotAcknowledged
    case credentialNotFound(CredentialID)
}

/// Quản lý scope (cấp thêm/thu hẹp), thu hồi credential, xóa account. Mọi rẽ nhánh theo
/// provider đi qua `ProviderQuirks` — không `if provider ==`.
public actor ScopeService {
    public static let dropboxConsoleURL = URL(string: "https://www.dropbox.com/developers/apps")!

    private let login: any LoginRunner
    private let providers: any ProviderRegistry
    private let clients: any OAuthClientRepository
    private let accounts: any AccountRepository
    private let credentials: any CredentialRepository
    private let secrets: SecretVault
    private let audit: any AuditLog
    private let tokenEndpoint: TokenEndpointClient
    private let tokens: TokenProvider
    private let clock: any DateProvider
    private let ids: any IDGenerator

    public init(
        login: any LoginRunner,
        providers: any ProviderRegistry,
        clients: any OAuthClientRepository,
        accounts: any AccountRepository,
        credentials: any CredentialRepository,
        secrets: SecretVault,
        audit: any AuditLog,
        tokenEndpoint: TokenEndpointClient,
        tokens: TokenProvider,
        clock: any DateProvider,
        ids: any IDGenerator
    ) {
        self.login = login
        self.providers = providers
        self.clients = clients
        self.accounts = accounts
        self.credentials = credentials
        self.secrets = secrets
        self.audit = audit
        self.tokenEndpoint = tokenEndpoint
        self.tokens = tokens
        self.clock = clock
        self.ids = ids
    }

    // MARK: - Scope

    public func missingScopes(_ account: AccountID) async throws -> ScopeSet {
        let (provider, granted) = try await providerAndGranted(account)
        return ScopeNormalizer.canonical(provider.defaultScopes, provider: provider)
            .missing(in: granted)
    }

    public func planGrantMore(
        _ account: AccountID, adding extra: ScopeSet = []
    ) async throws -> GrantMorePlan {
        let accountEntity = try await requireAccount(account)
        let provider = try await providers.provider(accountEntity.providerId)
        let client = try await requireClient(accountEntity.oauthClientId)
        let granted = (try await credentials.active(for: account))?.grantedScopes ?? []
        let email = accountEntity.email

        let need = ScopeNormalizer.canonical(
            provider.defaultScopes.union(extra), provider: provider)
        let missing = need.missing(in: granted)
        guard !missing.isEmpty else { return .nothingMissing }

        func request(scopes: ScopeSet, includeGranted: Bool) -> LoginRequest {
            LoginRequest(
                oauthClientId: client.id,
                scopes: scopes,
                target: .existing(account),
                includeGrantedScopes: includeGranted,
                loginHint: email)
        }

        switch provider.quirks.incrementalAuth {
        case .includeGrantedScopes:
            let scopes = missing.union(["openid", "email"])
            return .browser(request(scopes: scopes, includeGranted: true))
        case .reauthorize:
            let scopes = granted.union(missing)
            return .browser(request(scopes: scopes, includeGranted: false))
        case .consoleThenRelogin:
            return .consoleThenRelogin(
                consoleURL: Self.dropboxConsoleURL,
                missing: missing,
                then: request(scopes: need, includeGranted: false))
        }
    }

    /// Điểm vào DUY NHẤT cho mọi login từ UI (thêm account, re-auth, cấp thêm, thu hẹp).
    public func execute(_ request: LoginRequest) async throws -> LoginOutcome {
        let outcome = try await login.login(request)
        try await refreshAndCleanup(outcome.account.id)
        return outcome
    }

    public func reduce(_ account: AccountID, to scopes: ScopeSet) async throws -> LoginOutcome {
        let (provider, granted) = try await providerAndGranted(account)
        let accountEntity = try await requireAccount(account)
        let client = try await requireClient(accountEntity.oauthClientId)

        let extra = scopes.missing(in: granted)
        if !extra.isEmpty {
            throw ScopeServiceError.notSubset(extra: extra)
        }
        let dropped = granted.missing(in: scopes)

        // Dropbox: thu hồi credential CŨ TRƯỚC khi dọn giá trị secret của nó — vì revoke
        // cần refresh token cũ còn trong store. Login trực tiếp (không qua execute) để
        // giữ giá trị secret cũ tới bước này.
        let oldCredential = try await credentials.active(for: account)
        let outcome = try await login.login(
            LoginRequest(
                oauthClientId: client.id,
                scopes: scopes,
                target: .existing(account),
                includeGrantedScopes: false,
                loginHint: accountEntity.email))
        if case .dropboxAPI = provider.quirks.revocation, let old = oldCredential {
            try? await revokeAtProvider(credential: old, provider: provider)
            try? await finalizeRevocation(credential: old, provider: provider)
        }
        try await refreshAndCleanup(account)
        if !dropped.isEmpty {
            try await recordAudit(
                .scopeReduced, target: "account:\(account)", scopes: dropped, result: .success)
        }
        return outcome
    }

    // MARK: - Thu hồi

    public func revoke(
        _ credential: CredentialID, acknowledgeGrantWideRevocation: Bool
    ) async throws -> RevocationOutcome {
        guard let entity = try await credentials.get(credential) else {
            throw ScopeServiceError.credentialNotFound(credential)
        }
        let accountEntity = try await requireAccount(entity.accountId)
        let provider = try await providers.provider(accountEntity.providerId)

        if case .rfc7009(_, true) = provider.quirks.revocation,
            !acknowledgeGrantWideRevocation
        {
            throw ScopeServiceError.grantWideRevocationNotAcknowledged
        }

        let outcome = try await revokeAtProvider(credential: entity, provider: provider)

        if case .rfc7009(_, true) = provider.quirks.revocation {
            // Thu hồi cả grant → mọi credential của account chết cùng lúc.
            for sibling in try await credentials.list(for: entity.accountId)
            where sibling.status != .revoked {
                try await finalizeRevocation(credential: sibling, provider: provider)
            }
        }
        try await finalizeRevocation(credential: entity, provider: provider)
        return outcome
    }

    public func removeAccount(
        _ account: AccountID, acknowledgeGrantWideRevocation: Bool
    ) async throws -> RemovalReport {
        let accountEntity = try await requireAccount(account)
        let provider = try await providers.provider(accountEntity.providerId)
        let allCredentials = try await credentials.list(for: account)

        // Google (whole grant): chỉ revoke MỘT lần, cần ack TRƯỚC khi làm gì.
        var toRevoke = allCredentials
        if case .rfc7009(_, true) = provider.quirks.revocation {
            if !acknowledgeGrantWideRevocation {
                throw ScopeServiceError.grantWideRevocationNotAcknowledged
            }
            if let one = allCredentials.first(where: { $0.status == .active })
                ?? allCredentials.sorted(by: { $0.issuedAt > $1.issuedAt }).first
            {
                toRevoke = [one]
            } else {
                toRevoke = []
            }
        }

        var revocations: [CredentialID: RevocationOutcome] = [:]
        for credential in toRevoke {
            do {
                let outcome = try await revokeAtProvider(credential: credential, provider: provider)
                revocations[credential.id] = outcome
            } catch {
                // Lỗi mạng khi xóa account: đánh dấu localOnly và TIẾP TỤC.
                revocations[credential.id] = .localOnly(reason: "network")
            }
        }

        let secretIds = allCredentials.map(\.refreshTokenRef)
        // Thứ tự bắt buộc: account (cascade credential + health) TRƯỚC, secret SAU
        // (FK credential.refresh_token_ref là RESTRICT).
        try await accounts.delete(account)
        var leftover: [SecretID] = []
        for secretId in secretIds {
            do {
                try await secrets.delete(secretId, actor: .user)
            } catch {
                leftover.append(secretId)
            }
        }
        await tokens.invalidate(account)
        try await recordAudit(
            .accountRemoved, target: "account:\(account)", scopes: nil, result: .success)

        return RemovalReport(revocations: revocations, leftoverSecrets: leftover)
    }

    // MARK: - Nội bộ

    private func refreshAndCleanup(_ account: AccountID) async throws {
        await tokens.invalidate(account)
        do {
            _ = try await tokens.forceRefresh(for: account)
            try? await cleanupSuperseded(for: account)
        } catch {
            // Login đã thành công; refresh lỗi → không dọn secret cũ (giữ để dùng lại),
            // không throw — health check sẽ báo.
        }
    }

    /// Dọn giá trị Keychain của credential đã supersede; giữ hàng credential + metadata.
    private func cleanupSuperseded(for account: AccountID) async throws {
        for credential in try await credentials.list(for: account)
        where credential.status == .superseded {
            if try await secrets.exists(credential.refreshTokenRef) {
                try? await secrets.purgeValue(credential.refreshTokenRef, actor: .app)
            }
        }
    }

    private func revokeAtProvider(
        credential: Credential, provider: Provider
    ) async throws -> RevocationOutcome {
        switch provider.quirks.revocation {
        case .rfc7009(let url, _):
            let client = try await clientCredentials(for: credential.accountId)
            let token = try await readRefreshToken(credential)
            try await tokenEndpoint.revoke(
                token: token, tokenTypeHint: "refresh_token", style: .rfc7009(url, revokesWholeGrant: false),
                client: client)
            return .revokedRemotely
        case .dropboxAPI(let url):
            // Dropbox: refresh RT lấy access token rồi revoke bằng Bearer.
            let client = try await clientCredentials(for: credential.accountId)
            let refreshToken = try await readRefreshToken(credential)
            let response = try await tokenEndpoint.refresh(
                refreshToken, tokenURL: provider.tokenURL, client: client, scopes: nil)
            try await tokenEndpoint.revoke(
                token: response.accessToken, tokenTypeHint: "access_token",
                style: .dropboxAPI(url), client: client)
            return .revokedRemotely
        case .unsupported:
            return .localOnly(reason: "provider không hỗ trợ thu hồi")
        }
    }

    /// Đánh dấu revoked + dọn secret + invalidate + audit; account hết active → needsReauth.
    private func finalizeRevocation(credential: Credential, provider: Provider) async throws {
        try await credentials.markRevoked(credential.id)
        try? await secrets.purgeValue(credential.refreshTokenRef, actor: .app)
        await tokens.invalidate(credential.accountId)
        try await recordAudit(
            .credentialRevoked, target: "credential:\(credential.id)", scopes: nil, result: .success)
        if try await credentials.active(for: credential.accountId) == nil {
            try await accounts.updateStatus(credential.accountId, to: .needsReauth, at: clock.now())
        }
    }

    private func readRefreshToken(_ credential: Credential) async throws -> String {
        let data = try await secrets.read(
            credential.refreshTokenRef, reason: "Thu hồi token", actor: .app)
        return String(decoding: data, as: UTF8.self)
    }

    private func clientCredentials(for account: AccountID) async throws -> ClientCredentials {
        let accountEntity = try await requireAccount(account)
        let provider = try await providers.provider(accountEntity.providerId)
        guard let client = try await clients.get(accountEntity.oauthClientId) else {
            throw DomainError.notFound("oauth_client:\(accountEntity.oauthClientId)")
        }
        var secret: String?
        if let ref = client.clientSecretRef {
            let data = try await secrets.read(ref, reason: "Thu hồi token", actor: .app)
            secret = String(decoding: data, as: UTF8.self)
        }
        return ClientCredentials(
            clientId: client.clientId,
            clientSecret: secret,
            method: provider.quirks.tokenEndpointAuth)
    }

    private func providerAndGranted(_ account: AccountID) async throws -> (Provider, ScopeSet) {
        let accountEntity = try await requireAccount(account)
        let provider = try await providers.provider(accountEntity.providerId)
        let granted = (try await credentials.active(for: account))?.grantedScopes ?? []
        return (provider, granted)
    }

    private func requireAccount(_ id: AccountID) async throws -> Account {
        guard let account = try await accounts.get(id) else {
            throw DomainError.notFound("account:\(id)")
        }
        return account
    }

    private func requireClient(_ id: OAuthClientID) async throws -> OAuthClient {
        guard let client = try await clients.get(id) else {
            throw DomainError.notFound("oauth_client:\(id)")
        }
        return client
    }

    private func recordAudit(
        _ action: AuditAction, target: String, scopes: ScopeSet?, result: AuditResult
    ) async throws {
        try await audit.append(
            AuditEvent(
                id: AuditEventID(rawValue: ids.make()),
                actor: .user,
                action: action,
                target: target,
                scopes: scopes,
                result: result,
                timestamp: clock.now()))
    }
}
