import Foundation
import VaultDomain

public enum SecretVaultError: Error, Sendable, Equatable {
    case notFound(SecretID)
    case store(SecretStoreError)
    case metadata(String)
}

/// Facade duy nhất để tạo/đọc/xoay/xóa secret: ghi Keychain + metadata + audit luôn nhất quán.
/// Giá trị bí mật chỉ đi qua đây, không bao giờ nằm trong entity (DB chỉ có `KeychainRef`).
public actor SecretVault {
    public static let version = "0.1.0"

    private let store: any SecretStore
    private let metadata: any SecretMetadataRepository
    private let audit: any AuditLog
    private let clock: any DateProvider
    private let ids: any IDGenerator

    public init(
        store: any SecretStore,
        metadata: any SecretMetadataRepository,
        audit: any AuditLog,
        clock: any DateProvider,
        ids: any IDGenerator
    ) {
        self.store = store
        self.metadata = metadata
        self.audit = audit
        self.clock = clock
        self.ids = ids
    }

    /// Token của máy (refresh/client secret) đọc tự động; secret người nhập cần Touch ID.
    public static func defaultRequiresUserPresence(_ kind: SecretKind) -> Bool {
        switch kind {
        case .refreshToken, .clientSecret: false
        case .apiKey, .password: true
        }
    }

    public func create(
        kind: SecretKind,
        label: String,
        value: Data,
        requiresUserPresence: Bool? = nil,
        actor: AuditActor
    ) async throws -> Secret {
        let id = SecretID(rawValue: ids.make())
        let ref = KeychainRef(kind: kind, id: id)
        let presence = requiresUserPresence ?? Self.defaultRequiresUserPresence(kind)
        let policy: SecretAccessPolicy = presence ? .userPresence : .afterFirstUnlock

        do {
            try await store.set(value, for: ref, policy: policy)
        } catch let error as SecretStoreError {
            throw SecretVaultError.store(error)
        }

        let secret = Secret(
            id: id,
            kind: kind,
            label: label,
            keychainRef: ref,
            requiresUserPresence: presence,
            createdAt: clock.now())
        do {
            try await metadata.insert(secret)
        } catch {
            // Bồi hoàn item mồ côi trong Keychain; lỗi dọn không được che mất lỗi gốc.
            // try?: bồi hoàn khi metadata đã lỗi — xóa store lỗi không thay lỗi gốc được.
            try? await store.delete(ref)
            throw SecretVaultError.metadata("\(error)")
        }
        try await appendAudit(.secretCreated, target: "secret:\(id)", actor: actor)
        return secret
    }

    public func read(_ id: SecretID, reason: String, actor: AuditActor) async throws -> Data {
        guard let secret = try await metadata.get(id) else {
            throw SecretVaultError.notFound(id)
        }
        let value: Data
        do {
            value = try await store.get(secret.keychainRef, reason: reason)
        } catch let error as SecretStoreError {
            throw SecretVaultError.store(error)
        }
        // Đọc tự động trong app không ghi audit (tránh nhiễu); mọi actor ngoài ghi lại.
        if actor != .app {
            try await appendAudit(.secretRead, target: "secret:\(id)", actor: actor)
        }
        return value
    }

    public func rotate(_ id: SecretID, to value: Data, actor: AuditActor) async throws -> Secret {
        guard let secret = try await metadata.get(id) else {
            throw SecretVaultError.notFound(id)
        }
        let policy: SecretAccessPolicy =
            secret.requiresUserPresence ? .userPresence : .afterFirstUnlock
        do {
            try await store.set(value, for: secret.keychainRef, policy: policy)
        } catch let error as SecretStoreError {
            throw SecretVaultError.store(error)
        }
        let rotatedAt = clock.now()
        do {
            try await metadata.markRotated(id, at: rotatedAt)
        } catch {
            throw SecretVaultError.metadata("\(error)")
        }
        try await appendAudit(.secretRotated, target: "secret:\(id)", actor: actor)
        var updated = secret
        updated.rotatedAt = rotatedAt
        return updated
    }

    public func delete(_ id: SecretID, actor: AuditActor) async throws {
        guard let secret = try await metadata.get(id) else {
            throw SecretVaultError.notFound(id)
        }
        do {
            try await store.delete(secret.keychainRef)
        } catch let error as SecretStoreError {
            throw SecretVaultError.store(error)
        }
        do {
            try await metadata.delete(id)
        } catch {
            throw SecretVaultError.metadata("\(error)")
        }
        try await appendAudit(.secretDeleted, target: "secret:\(id)", actor: actor)
    }

    /// Xóa GIÁ TRỊ trong store nhưng giữ metadata (hàng credential còn tham chiếu FK
    /// RESTRICT, và giữ lịch sử). Dọn credential đã supersede.
    public func purgeValue(_ id: SecretID, actor: AuditActor) async throws {
        guard let secret = try await metadata.get(id) else {
            throw SecretVaultError.notFound(id)
        }
        do {
            try await store.delete(secret.keychainRef)
        } catch let error as SecretStoreError {
            throw SecretVaultError.store(error)
        }
        do {
            try await metadata.markRotated(id, at: clock.now())
        } catch {
            throw SecretVaultError.metadata("\(error)")
        }
        try await appendAudit(.secretDeleted, target: "secret:\(id)", actor: actor)
    }

    /// Metadata có mặt VÀ item còn trong store.
    public func exists(_ id: SecretID) async throws -> Bool {
        guard let secret = try await metadata.get(id) else { return false }
        return try await store.contains(secret.keychainRef)
    }

    public func list(kind: SecretKind?) async throws -> [Secret] {
        try await metadata.list(kind: kind)
    }

    /// Audit là yêu cầu bảo mật: lỗi ghi audit phải throw, không im lặng bỏ qua.
    private func appendAudit(
        _ action: AuditAction, target: String, actor: AuditActor
    ) async throws {
        do {
            try await audit.append(
                AuditEvent(
                    id: AuditEventID(rawValue: ids.make()),
                    actor: actor,
                    action: action,
                    target: target,
                    result: .success,
                    timestamp: clock.now()))
        } catch {
            throw SecretVaultError.metadata("audit: \(error)")
        }
    }
}
