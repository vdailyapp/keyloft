import Foundation
import VaultDomain

/// Kho chung cho các InMemory repository: chia sẻ state để bắt được quan hệ
/// (hasDependents, cascade) giống GRDB thật ở SPEC-003 §4.
/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class InMemoryDatabase: @unchecked Sendable {
    struct Store {
        var clients: [OAuthClientID: OAuthClient] = [:]
        var accounts: [AccountID: Account] = [:]
        var credentials: [CredentialID: Credential] = [:]
        var secrets: [SecretID: Secret] = [:]
        var healthChecks: [HealthCheckResult] = []
        var auditEvents: [AuditEvent] = []
    }

    let lock = NSLock()
    var store = Store()

    public init() {}

    func withLock<T>(_ body: (inout Store) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&store)
    }
}

/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class InMemoryOAuthClientRepository: OAuthClientRepository, @unchecked Sendable {
    let db: InMemoryDatabase

    public init(db: InMemoryDatabase = InMemoryDatabase()) { self.db = db }

    public func save(_ client: OAuthClient) async throws {
        db.withLock { $0.clients[client.id] = client }
    }

    public func get(_ id: OAuthClientID) async throws -> OAuthClient? {
        db.withLock { $0.clients[id] }
    }

    public func list(provider: ProviderID?) async throws -> [OAuthClient] {
        db.withLock { store in
            store.clients.values
                .filter { provider == nil || $0.providerId == provider }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    public func delete(_ id: OAuthClientID) async throws {
        try db.withLock { store in
            if store.accounts.values.contains(where: { $0.oauthClientId == id }) {
                throw DomainError.hasDependents("oauth_client:\(id)")
            }
            store.clients[id] = nil
        }
    }
}

/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class InMemoryAccountRepository: AccountRepository, @unchecked Sendable {
    let db: InMemoryDatabase

    public init(db: InMemoryDatabase = InMemoryDatabase()) { self.db = db }

    public func save(_ account: Account) async throws {
        db.withLock { $0.accounts[account.id] = account }
    }

    public func get(_ id: AccountID) async throws -> Account? {
        db.withLock { $0.accounts[id] }
    }

    public func find(provider: ProviderID, oauthClient: OAuthClientID, externalId: String) async throws -> Account? {
        db.withLock { store in
            store.accounts.values.first {
                $0.providerId == provider && $0.oauthClientId == oauthClient && $0.externalId == externalId
            }
        }
    }

    public func list() async throws -> [Account] {
        db.withLock { store in
            store.accounts.values.sorted { $0.createdAt < $1.createdAt }
        }
    }

    public func updateStatus(_ id: AccountID, to status: AccountStatus, at date: Date) async throws {
        try db.withLock { store in
            guard store.accounts[id] != nil else {
                throw DomainError.notFound("account:\(id)")
            }
            store.accounts[id]?.status = status
            store.accounts[id]?.statusChangedAt = date
        }
    }

    public func delete(_ id: AccountID) async throws {
        try db.withLock { store in
            guard store.accounts[id] != nil else {
                throw DomainError.notFound("account:\(id)")
            }
            // Cascade như ON DELETE CASCADE của GRDB.
            store.accounts[id] = nil
            store.credentials = store.credentials.filter { $0.value.accountId != id }
            store.healthChecks = store.healthChecks.filter { $0.accountId != id }
        }
    }
}

/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class InMemoryCredentialRepository: CredentialRepository, @unchecked Sendable {
    let db: InMemoryDatabase

    public init(db: InMemoryDatabase = InMemoryDatabase()) { self.db = db }

    public func insert(_ credential: Credential) async throws {
        try db.withLock { store in
            guard store.credentials[credential.id] == nil else {
                throw DomainError.invariantViolated("credential:\(credential.id) đã tồn tại")
            }
            store.credentials[credential.id] = credential
        }
    }

    public func get(_ id: CredentialID) async throws -> Credential? {
        db.withLock { $0.credentials[id] }
    }

    public func active(for account: AccountID) async throws -> Credential? {
        db.withLock { store in
            store.credentials.values
                .filter { $0.accountId == account && $0.status == .active }
                .max { $0.issuedAt < $1.issuedAt }
        }
    }

    public func list(for account: AccountID) async throws -> [Credential] {
        db.withLock { store in
            store.credentials.values
                .filter { $0.accountId == account }
                .sorted { $0.issuedAt < $1.issuedAt }
        }
    }

    public func markSuperseded(_ id: CredentialID, by newId: CredentialID) async throws {
        try db.withLock { store in
            guard store.credentials[id] != nil else {
                throw DomainError.notFound("credential:\(id)")
            }
            store.credentials[id]?.status = .superseded
            store.credentials[id]?.supersededBy = newId
        }
    }

    public func markRevoked(_ id: CredentialID) async throws {
        try db.withLock { store in
            guard store.credentials[id] != nil else {
                throw DomainError.notFound("credential:\(id)")
            }
            store.credentials[id]?.status = .revoked
        }
    }

    public func updateGrantedScopes(_ id: CredentialID, _ scopes: ScopeSet) async throws {
        try db.withLock { store in
            guard store.credentials[id] != nil else {
                throw DomainError.notFound("credential:\(id)")
            }
            store.credentials[id]?.grantedScopes = scopes
        }
    }
}

/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class InMemorySecretMetadataRepository: SecretMetadataRepository, @unchecked Sendable {
    let db: InMemoryDatabase

    public init(db: InMemoryDatabase = InMemoryDatabase()) { self.db = db }

    public func insert(_ secret: Secret) async throws {
        try db.withLock { store in
            guard !store.secrets.values.contains(where: { $0.keychainRef == secret.keychainRef }) else {
                throw DomainError.invariantViolated("secret ref trùng: \(secret.keychainRef.account)")
            }
            store.secrets[secret.id] = secret
        }
    }

    public func get(_ id: SecretID) async throws -> Secret? {
        db.withLock { $0.secrets[id] }
    }

    public func list(kind: SecretKind?) async throws -> [Secret] {
        db.withLock { store in
            store.secrets.values
                .filter { kind == nil || $0.kind == kind }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    public func markRotated(_ id: SecretID, at date: Date) async throws {
        try db.withLock { store in
            guard store.secrets[id] != nil else {
                throw DomainError.notFound("secret:\(id)")
            }
            store.secrets[id]?.rotatedAt = date
        }
    }

    public func delete(_ id: SecretID) async throws {
        try db.withLock { store in
            // Như ON DELETE RESTRICT của credential.refresh_token_ref.
            if store.credentials.values.contains(where: { $0.refreshTokenRef == id }) {
                throw DomainError.hasDependents("secret:\(id)")
            }
            store.secrets[id] = nil
        }
    }
}

/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class InMemoryHealthCheckRepository: HealthCheckRepository, @unchecked Sendable {
    let db: InMemoryDatabase

    public init(db: InMemoryDatabase = InMemoryDatabase()) { self.db = db }

    public func append(_ result: HealthCheckResult) async throws {
        db.withLock { store in
            store.healthChecks.append(result)
            // Giữ 50 bản mới nhất mỗi account (SPEC-003 §4).
            let forAccount = store.healthChecks.filter { $0.accountId == result.accountId }
                .sorted { $0.checkedAt < $1.checkedAt }
            if forAccount.count > HealthCheckRetention.perAccount {
                let toDrop = Set(forAccount.prefix(forAccount.count - HealthCheckRetention.perAccount).map(\.id))
                store.healthChecks.removeAll { toDrop.contains($0.id) }
            }
        }
    }

    public func latest(for account: AccountID) async throws -> HealthCheckResult? {
        db.withLock { store in
            store.healthChecks
                .filter { $0.accountId == account }
                .max { $0.checkedAt < $1.checkedAt }
        }
    }

    public func list(for account: AccountID, limit: Int) async throws -> [HealthCheckResult] {
        db.withLock { store in
            Array(
                store.healthChecks
                    .filter { $0.accountId == account }
                    .sorted { $0.checkedAt > $1.checkedAt }
                    .prefix(limit))
        }
    }
}

/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class InMemoryAuditLog: AuditLog, @unchecked Sendable {
    let db: InMemoryDatabase

    public init(db: InMemoryDatabase = InMemoryDatabase()) { self.db = db }

    public func append(_ event: AuditEvent) async throws {
        db.withLock { $0.auditEvents.append(event) }
    }

    public func query(_ query: AuditQuery) async throws -> [AuditEvent] {
        db.withLock { store in
            Array(
                store.auditEvents
                    .filter { event in
                        (query.target == nil || event.target == query.target)
                            && (query.actions == nil || query.actions!.contains(event.action))
                            && (query.since == nil || event.timestamp >= query.since!)
                    }
                    .sorted { $0.timestamp > $1.timestamp }
                    .prefix(query.limit))
        }
    }
}

/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class InMemoryProviderRegistry: ProviderRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var providers: [ProviderID: Provider]

    public init(_ providers: [Provider] = []) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    public func provider(_ id: ProviderID) async throws -> Provider {
        try withLock {
            guard let provider = providers[id] else {
                throw DomainError.notFound("provider:\(id.rawValue)")
            }
            return provider
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
