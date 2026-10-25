import Foundation
import SecretVault
import VaultDomain

/// SecretStore giả: dict trong RAM. `presenceGranted = false` giả lập người dùng hủy Touch ID.
public actor InMemorySecretStore: SecretStore {
    private var items: [KeychainRef: (data: Data, policy: SecretAccessPolicy)] = [:]
    private var getCountValue = 0
    private var presenceGranted = true
    private var failNextSet: SecretStoreError?

    public init() {}

    public func set(_ data: Data, for ref: KeychainRef, policy: SecretAccessPolicy) async throws {
        if let failure = failNextSet {
            failNextSet = nil
            throw failure
        }
        items[ref] = (data, policy)
    }

    public func get(_ ref: KeychainRef, reason: String) async throws -> Data {
        getCountValue += 1
        guard let item = items[ref] else { throw SecretStoreError.notFound }
        if item.policy == .userPresence && !presenceGranted {
            throw SecretStoreError.userCanceled
        }
        return item.data
    }

    public func delete(_ ref: KeychainRef) async throws {
        items[ref] = nil
    }

    public func contains(_ ref: KeychainRef) async throws -> Bool {
        items[ref] != nil
    }

    // MARK: - Điều khiển test

    public var getCount: Int { getCountValue }

    public var storedRefs: [KeychainRef] { Array(items.keys) }

    public func setPresenceGranted(_ granted: Bool) {
        presenceGranted = granted
    }

    /// Lần `set` kế tiếp throw lỗi này (một lần).
    public func setFailNextSet(_ error: SecretStoreError?) {
        failNextSet = error
    }

    /// Xóa tay item (giả lập item bị mất ngoài vault).
    public func remove(_ ref: KeychainRef) {
        items[ref] = nil
    }
}
