import Foundation
import VaultDomain

/// Khi nào item Keychain cho phép đọc.
public enum SecretAccessPolicy: Sendable, Equatable {
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
    case afterFirstUnlock
    /// `SecAccessControl(kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence)`.
    case userPresence
}

/// Hậu trường lưu trữ giá trị bí mật. Keychain thật ở T08; test dùng InMemorySecretStore.
public protocol SecretStore: Sendable {
    /// Ghi đè nếu đã có (delete + add, vì access control không update được).
    func set(_ data: Data, for ref: KeychainRef, policy: SecretAccessPolicy) async throws
    /// `reason` hiện trong hộp thoại Touch ID nếu item cần presence.
    func get(_ ref: KeychainRef, reason: String) async throws -> Data
    /// Item không tồn tại → không lỗi.
    func delete(_ ref: KeychainRef) async throws
    /// Không bao giờ hiện UI xác thực.
    func contains(_ ref: KeychainRef) async throws -> Bool
}

public enum SecretStoreError: Error, Sendable, Equatable {
    case notFound
    /// errSecUserCanceled (-128).
    case userCanceled
    case authFailed
    /// Vault khóa / máy khóa (errSecInteractionNotAllowed).
    case interactionNotAllowed
    /// Build chưa ký (errSecMissingEntitlement -34018).
    case missingEntitlement
    case osStatus(Int32)
}
