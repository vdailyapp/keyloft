import Foundation
import Providers
import TokenVault
import VaultDomain

/// Tạo probe theo provider (test bơm FakeProbe).
public typealias ProbeResolver = @Sendable (ProviderID) -> any APIProbe

/// Kiểm tra 5 tầng theo thứ tự, dừng ở tầng lỗi đầu tiên; lưu kết quả và đổi status account.
/// Chỉ throw khi account không tồn tại hoặc lỗi hạ tầng — lỗi của tầng là DỮ LIỆU trong checks.
public actor HealthChecker {
    private let accounts: any AccountRepository
    private let credentials: any CredentialRepository
    private let clients: any OAuthClientRepository
    /// Closure thay vì `SecretVault` trực tiếp: HealthCheck không được phụ thuộc SecretVault
    /// trong đồ thị SPM (chỉ T01 được sửa Package.swift).
    private let secretExists: @Sendable (SecretID) async throws -> Bool
    private let tokens: TokenProvider
    private let providers: any ProviderRegistry
    private let probes: ProbeResolver
    private let results: any HealthCheckRepository
    private let audit: any AuditLog
    private let clock: any DateProvider
    private let ids: any IDGenerator
    private let policy: HealthPolicy

    public init(
        accounts: any AccountRepository,
        credentials: any CredentialRepository,
        clients: any OAuthClientRepository,
        secretExists: @escaping @Sendable (SecretID) async throws -> Bool,
        tokens: TokenProvider,
        providers: any ProviderRegistry,
        probes: @escaping ProbeResolver,
        results: any HealthCheckRepository,
        audit: any AuditLog,
        clock: any DateProvider,
        ids: any IDGenerator,
        policy: HealthPolicy = HealthPolicy()
    ) {
        self.accounts = accounts
        self.credentials = credentials
        self.clients = clients
        self.secretExists = secretExists
        self.tokens = tokens
        self.providers = providers
        self.probes = probes
        self.results = results
        self.audit = audit
        self.clock = clock
        self.ids = ids
        self.policy = policy
    }

    public func check(_ account: AccountID, actor auditActor: AuditActor) async throws -> HealthCheckResult {
        guard let accountEntity = try await accounts.get(account) else {
            throw DomainError.notFound("account:\(account)")
        }
        let provider = try await providers.provider(accountEntity.providerId)
        let client = try await clients.get(accountEntity.oauthClientId)

        var checks: [HealthCheckItem] = []
        var failure: LayerFailure?
        var warnings: [String] = []

        // Tầng 1: refresh token có trong metadata VÀ còn trong store.
        let credential = try await credentials.active(for: account)
        if let credential {
            let exists = try await secretExists(credential.refreshTokenRef)
            if exists {
                checks.append(HealthCheckItem(name: .tokenPresent, ok: true))
            } else {
                failure = .noRefreshToken
                checks.append(HealthCheckItem(name: .tokenPresent, ok: false, error: failure?.label))
            }
        } else {
            failure = .noRefreshToken
            checks.append(HealthCheckItem(name: .tokenPresent, ok: false, error: failure?.label))
        }

        // Tầng 2: force refresh chứng minh refresh token còn sống.
        var refreshedToken: AccessToken?
        if failure == nil {
            let started = clock.now()
            do {
                refreshedToken = try await tokens.forceRefresh(for: account)
                let latency = Int(clock.now().timeIntervalSince(started) * 1000)
                checks.append(HealthCheckItem(name: .refresh, ok: true, latencyMs: latency))
            } catch let error as TokenVaultError {
                failure = layerFailure(for: error)
                checks.append(HealthCheckItem(name: .refresh, ok: false, error: failure?.label))
            }
        }

        // Tầng 3: gọi API thật của provider.
        var probeResult: ProbeResult?
        if failure == nil, let token = refreshedToken {
            do {
                let result = try await probes(provider.id).probe(accessToken: token.value)
                probeResult = result
                checks.append(HealthCheckItem(name: .apiCall, ok: true, latencyMs: result.latencyMs))
            } catch let error as ProbeError {
                failure = layerFailure(for: error)
                checks.append(HealthCheckItem(name: .apiCall, ok: false, error: failure?.label))
            }
        }

        // Tầng 4: scope đủ (đọc lại credential SAU refresh vì refresh có thể thu hẹp).
        if failure == nil {
            let fresh = try await credentials.active(for: account)
            let granted = fresh?.grantedScopes ?? []
            let required = ScopeNormalizer.canonical(provider.defaultScopes, provider: provider)
            let missing = required.missing(in: granted)
            if missing.isEmpty {
                checks.append(HealthCheckItem(name: .scopes, ok: true))
            } else {
                failure = .missingScopes(missing)
                checks.append(HealthCheckItem(name: .scopes, ok: false, error: failure?.label))
            }
        }

        // Tầng 5: cảnh báo sớm (chỉ chạy khi qua 4 tầng).
        if failure == nil {
            if let quota = probeResult?.quota, let total = quota.total, total > 0,
                Double(quota.used) / Double(total) > policy.quotaWarnRatio
            {
                warnings.append("quota>\(Int(policy.quotaWarnRatio * 100))%")
            }
            if let expires = client?.secretExpiresAt {
                let remaining = expires.timeIntervalSince(clock.now())
                if remaining < 0 {
                    warnings.append("clientSecretExpired")
                } else if remaining < policy.secretExpiryWarn {
                    warnings.append("clientSecret<30d")
                }
            }
            if let latency = probeResult?.latencyMs, latency > policy.slowThresholdMs {
                warnings.append("slow")
            }
            checks.append(
                HealthCheckItem(name: .earlyWarning, ok: true, latencyMs: probeResult?.latencyMs, warnings: warnings))
        }

        let newStatus = status(for: failure, warnings: warnings)
        let result = HealthCheckResult(
            id: HealthCheckID(rawValue: ids.make()),
            accountId: account,
            checkedAt: clock.now(),
            status: newStatus,
            checks: checks)
        try await results.append(result)

        if newStatus != accountEntity.status {
            try await accounts.updateStatus(account, to: newStatus, at: clock.now())
            try await audit.append(
                AuditEvent(
                    id: AuditEventID(rawValue: ids.make()),
                    actor: auditActor,
                    action: .accountStatusChanged,
                    target: "account:\(account)",
                    result: .success,
                    timestamp: clock.now()))
        }
        return result
    }
}
