import Foundation

public protocol OAuthClientRepository: Sendable {
    /// Upsert theo id.
    func save(_ client: OAuthClient) async throws
    func get(_ id: OAuthClientID) async throws -> OAuthClient?
    func list(provider: ProviderID?) async throws -> [OAuthClient]
    /// Còn Account phụ thuộc → throw `DomainError.hasDependents`.
    func delete(_ id: OAuthClientID) async throws
}

public protocol AccountRepository: Sendable {
    func save(_ account: Account) async throws
    func get(_ id: AccountID) async throws -> Account?
    func find(provider: ProviderID, oauthClient: OAuthClientID, externalId: String) async throws -> Account?
    /// Sắp theo createdAt.
    func list() async throws -> [Account]
    func updateStatus(_ id: AccountID, to status: AccountStatus, at: Date) async throws
    /// Cascade credential + health result.
    func delete(_ id: AccountID) async throws
}

public protocol CredentialRepository: Sendable {
    func insert(_ credential: Credential) async throws
    func get(_ id: CredentialID) async throws -> Credential?
    /// status == .active, issuedAt mới nhất.
    func active(for account: AccountID) async throws -> Credential?
    func list(for account: AccountID) async throws -> [Credential]
    func markSuperseded(_ id: CredentialID, by newId: CredentialID) async throws
    func markRevoked(_ id: CredentialID) async throws
    func updateGrantedScopes(_ id: CredentialID, _ scopes: ScopeSet) async throws
}

public protocol SecretMetadataRepository: Sendable {
    func insert(_ secret: Secret) async throws
    func get(_ id: SecretID) async throws -> Secret?
    func list(kind: SecretKind?) async throws -> [Secret]
    func markRotated(_ id: SecretID, at: Date) async throws
    func delete(_ id: SecretID) async throws
}

public protocol HealthCheckRepository: Sendable {
    /// Ghi thêm và giữ tối đa `HealthCheckRetention.perAccount` bản mới nhất cho account.
    func append(_ result: HealthCheckResult) async throws
    func latest(for account: AccountID) async throws -> HealthCheckResult?
    /// Mới nhất trước.
    func list(for account: AccountID, limit: Int) async throws -> [HealthCheckResult]
}

public enum HealthCheckRetention {
    public static let perAccount = 50
}

public struct AuditQuery: Sendable, Equatable {
    public var target: String?
    public var actions: Set<AuditAction>?
    public var since: Date?
    public var limit: Int = 200

    public init(target: String? = nil, actions: Set<AuditAction>? = nil, since: Date? = nil, limit: Int = 200) {
        self.target = target
        self.actions = actions
        self.since = since
        self.limit = limit
    }
}

public protocol AuditLog: Sendable {
    /// Chỉ ghi thêm, không có update/delete.
    func append(_ event: AuditEvent) async throws
    /// Mới nhất trước.
    func query(_ query: AuditQuery) async throws -> [AuditEvent]
}

/// TokenVault không được import Providers nên tra cứu provider đi qua protocol này;
/// `Providers.ProviderCatalog` (SPEC-007) implement, test dùng `InMemoryProviderRegistry`.
public protocol ProviderRegistry: Sendable {
    /// Không có → throw `DomainError.notFound("provider:<id>")`.
    func provider(_ id: ProviderID) async throws -> Provider
}
