import Foundation
import LocalAuthentication
import Security
import VaultDomain

public struct KeychainConfiguration: Sendable {
    public var service: String
    /// `"<TEAMID>.app.vdaily.keyloft"` khi app đã ký; nil cho dev/CLI.
    public var accessGroup: String?
    /// true cho app đã ký (Data Protection Keychain); false = login keychain (dev/CLI/test).
    public var useDataProtectionKeychain: Bool

    public init(
        service: String = KeychainRef.service,
        accessGroup: String? = nil,
        useDataProtectionKeychain: Bool = false
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }
}

/// Tách khỏi VaultLock (T09) để KeychainSecretStore không phụ thuộc VaultLock.
public protocol KeychainAuthContextProvider: Sendable {
    /// Context đã xác thực còn hiệu lực, hoặc nil nếu Vault đang khóa.
    func currentContext() async -> LAContext?
}

/// Keychain thật qua SecItem. SecItem là blocking nhưng chờ ngắn (trừ khi chờ Touch ID,
/// khi đó nằm trong actor riêng, không chặn MainActor của app).
public actor KeychainSecretStore: SecretStore {
    private let configuration: KeychainConfiguration
    private let contextProvider: (any KeychainAuthContextProvider)?

    public init(
        configuration: KeychainConfiguration,
        contextProvider: (any KeychainAuthContextProvider)? = nil
    ) {
        self.configuration = configuration
        self.contextProvider = contextProvider
    }

    public func set(_ data: Data, for ref: KeychainRef, policy: SecretAccessPolicy) async throws {
        // Access control không update được → xóa rồi thêm lại.
        try await delete(ref)

        var query = KeychainQuery.base(for: ref, configuration: configuration)
        query[kSecValueData as String] = data
        switch policy {
        case .afterFirstUnlock:
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .userPresence:
            var cfError: Unmanaged<CFError>?
            guard
                let access = SecAccessControlCreateWithFlags(
                    nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &cfError)
            else {
                let code = (cfError?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? -1
                throw SecretStoreError.osStatus(Int32(clamping: code))
            }
            query[kSecAttrAccessControl as String] = access
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainQuery.map(status)
        }
    }

    public func get(_ ref: KeychainRef, reason: String) async throws -> Data {
        var query = KeychainQuery.base(for: ref, configuration: configuration)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        if let context = await contextProvider?.currentContext() {
            // Vault đang mở (đã xác thực gần đây) — dùng lại context, không hỏi lại.
            query[kSecUseAuthenticationContext as String] = context
        } else {
            // kSecUseOperationPrompt đã deprecated: dùng context mới + localizedReason.
            let context = LAContext()
            context.localizedReason = reason
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw KeychainQuery.map(status)
        }
        guard let data = result as? Data else {
            // Về nguyên lý không xảy ra với kSecReturnData; giữ lỗi rõ ràng thay vì crash.
            throw SecretStoreError.authFailed
        }
        return data
    }

    public func delete(_ ref: KeychainRef) async throws {
        let status = SecItemDelete(
            KeychainQuery.base(for: ref, configuration: configuration) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainQuery.map(status)
        }
    }

    public func contains(_ ref: KeychainRef) async throws -> Bool {
        var query = KeychainQuery.base(for: ref, configuration: configuration)
        query[kSecReturnAttributes as String] = true
        // Context cấm tương tác: item presence vẫn trả success/interactionNotAllowed
        // mà KHÔNG hiện UI.
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess, errSecInteractionNotAllowed: return true
        case errSecItemNotFound: return false
        default: throw KeychainQuery.map(status)
        }
    }
}
