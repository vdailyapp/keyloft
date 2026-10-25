import Foundation
import SecretVault
import VaultDomain

/// Cấp access token: cache RAM + single-flight refresh + xoay vòng refresh token.
///
/// Reentrancy: actor có thể chen giữa các `await`, nhưng `joinOrStartRefresh` kiểm tra
/// `inFlight` TRƯỚC await đầu tiên nên không bao giờ sinh refresh thứ hai. Task refresh là
/// unstructured: caller bị hủy không hủy task — chờ `task.value` không lan truyền hủy.
public actor TokenProvider {
    public static let defaultMinValidity: TimeInterval = 60
    public static let rotationRetries = 3

    private let providers: any ProviderRegistry
    private let clients: any OAuthClientRepository
    private let accounts: any AccountRepository
    private let credentials: any CredentialRepository
    private let secrets: SecretVault
    private let audit: any AuditLog
    private let tokenEndpoint: TokenEndpointClient
    private let clock: any DateProvider
    private let ids: any IDGenerator

    private var cache: [AccountID: AccessToken] = [:]
    private var inFlight: [AccountID: Task<AccessToken, any Error>] = [:]

    public init(
        providers: any ProviderRegistry,
        clients: any OAuthClientRepository,
        accounts: any AccountRepository,
        credentials: any CredentialRepository,
        secrets: SecretVault,
        audit: any AuditLog,
        tokenEndpoint: TokenEndpointClient,
        clock: any DateProvider,
        ids: any IDGenerator
    ) {
        self.providers = providers
        self.clients = clients
        self.accounts = accounts
        self.credentials = credentials
        self.secrets = secrets
        self.audit = audit
        self.tokenEndpoint = tokenEndpoint
        self.clock = clock
        self.ids = ids
    }

    public func accessToken(
        for account: AccountID, minValidity: TimeInterval = TokenProvider.defaultMinValidity
    ) async throws -> AccessToken {
        if let token = cache[account], token.isValid(at: clock.now(), minValidity: minValidity) {
            return token
        }
        return try await joinOrStartRefresh(account)
    }

    /// Bỏ qua cache (health check tầng 2) — vẫn single-flight với `accessToken`.
    public func forceRefresh(for account: AccountID) async throws -> AccessToken {
        try await joinOrStartRefresh(account)
    }

    /// Dùng làm `onCredentialIssued` của OAuthLoginService.
    public func seed(_ token: AccessToken, for account: AccountID) {
        cache[account] = token
        inFlight[account] = nil
    }

    public func invalidate(_ account: AccountID) {
        cache[account] = nil
    }

    public func cachedToken(for account: AccountID) -> AccessToken? {
        cache[account]
    }

    // MARK: - Single-flight

    private func joinOrStartRefresh(_ account: AccountID) async throws -> AccessToken {
        if let running = inFlight[account] {
            return try await running.value
        }
        let task = Task { try await self.refreshAndClear(account) }
        inFlight[account] = task
        return try await task.value
    }

    /// Xóa `inFlight` khi refresh KẾT THÚC (trong task), không phải khi caller rời await —
    /// caller bị hủy giữa chừng không được xóa entry của task còn chạy.
    private func refreshAndClear(_ account: AccountID) async throws -> AccessToken {
        defer { inFlight[account] = nil }
        return try await performRefresh(account)
    }

    // MARK: - Refresh

    private func performRefresh(_ account: AccountID) async throws -> AccessToken {
        guard let accountEntity = try await accounts.get(account) else {
            throw TokenVaultError.accountNotFound(account)
        }
        guard let credential = try await credentials.active(for: account) else {
            throw TokenVaultError.noActiveCredential(account)
        }
        guard let client = try await clients.get(accountEntity.oauthClientId) else {
            throw TokenVaultError.accountNotFound(account)
        }
        let provider = try await providers.provider(accountEntity.providerId)

        let clientSecret: String?
        if let secretRef = client.clientSecretRef {
            let data: Data
            do {
                data = try await secrets.read(secretRef, reason: "Refresh token", actor: .app)
            } catch {
                throw TokenVaultError.secret("\(error)")
            }
            clientSecret = String(decoding: data, as: UTF8.self)
        } else {
            clientSecret = nil
        }

        let refreshTokenData: Data
        do {
            refreshTokenData = try await secrets.read(
                credential.refreshTokenRef, reason: "Làm mới token", actor: .app)
        } catch {
            throw TokenVaultError.secret("\(error)")
        }
        let currentRefreshToken = String(decoding: refreshTokenData, as: UTF8.self)

        let response: TokenResponse
        do {
            response = try await tokenEndpoint.refresh(
                currentRefreshToken,
                tokenURL: provider.tokenURL,
                client: ClientCredentials(
                    clientId: client.clientId,
                    clientSecret: clientSecret,
                    method: provider.quirks.tokenEndpointAuth),
                scopes: provider.quirks.refreshIncludesScope ? credential.grantedScopes : nil)
        } catch let error as OAuthError {
            switch error {
            case .invalidGrant:
                try? await accounts.updateStatus(account, to: .needsReauth, at: clock.now())
                cache[account] = nil
                try await appendRefreshFailure(account, "invalid_grant")
                throw TokenVaultError.oauth(error)
            case .invalidClient:
                try await accounts.updateStatus(account, to: .degraded, at: clock.now())
                try await appendRefreshFailure(account, "invalid_client")
                throw TokenVaultError.oauth(error)
            default:
                // Lỗi tạm thời (mạng/5xx) và mọi lỗi khác: KHÔNG đổi status, không audit.
                throw TokenVaultError.oauth(error)
            }
        }

        // Xoay vòng: provider trả refresh token mới → lưu ngay trước khi trả token.
        if let rotated = response.refreshToken, rotated != currentRefreshToken {
            var persisted = false
            for _ in 0..<Self.rotationRetries {
                do {
                    _ = try await secrets.rotate(
                        credential.refreshTokenRef, to: Data(rotated.utf8), actor: .app)
                    persisted = true
                    break
                } catch {
                    // Thử lại; lỗi cụ thể không quan trọng bằng việc lưu được token mới.
                    continue
                }
            }
            if !persisted {
                try await accounts.updateStatus(account, to: .needsReauth, at: clock.now())
                cache[account] = nil
                try await appendRefreshFailure(account, "rotation_persist_failed")
                throw TokenVaultError.rotationPersistFailed(account)
            }
        }

        // Scope có thể bị thu hẹp/mở rộng từ bên ngoài (consent screen).
        var granted = credential.grantedScopes
        if response.scope != nil {
            granted = ScopeNormalizer.granted(
                responseScope: response.scope,
                requested: credential.grantedScopes,
                provider: provider)
            let lost = credential.grantedScopes.missing(in: granted)
            if !lost.isEmpty {
                try await credentials.updateGrantedScopes(credential.id, granted)
                try await appendAudit(
                    account, action: .scopeReduced, scopes: lost, result: .success)
            } else if granted != credential.grantedScopes {
                try await credentials.updateGrantedScopes(credential.id, granted)
            }
        }

        let token = AccessToken(
            value: response.accessToken,
            scopes: granted,
            expiresAt: clock.now().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600)))
        cache[account] = token
        return token
    }

    private func appendRefreshFailure(_ account: AccountID, _ reason: String) async throws {
        try await appendAudit(account, action: .tokenRefreshFailed, scopes: nil, result: .failure(reason: reason))
    }

    private func appendAudit(
        _ account: AccountID, action: AuditAction, scopes: ScopeSet?, result: AuditResult
    ) async throws {
        try await audit.append(
            AuditEvent(
                id: AuditEventID(rawValue: ids.make()),
                actor: .app,
                action: action,
                target: "account:\(account)",
                scopes: scopes,
                result: result,
                timestamp: clock.now()))
    }
}
