import Foundation
import Security
import VaultDomain

/// Xây query SecItem cơ bản và map OSStatus → SecretStoreError.
enum KeychainQuery {
    static func base(for ref: KeychainRef, configuration: KeychainConfiguration) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
            kSecAttrAccount as String: ref.account,
            kSecAttrSynchronizable as String: false,
        ]
        // Chỉ đặt khi bật: false là mặc định của hệ thống.
        if configuration.useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        if let group = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    static func map(_ status: OSStatus) -> SecretStoreError {
        switch status {
        case errSecItemNotFound: .notFound
        case errSecUserCanceled: .userCanceled
        case errSecAuthFailed: .authFailed
        case errSecInteractionNotAllowed: .interactionNotAllowed
        case errSecMissingEntitlement: .missingEntitlement
        default: .osStatus(status)
        }
    }
}
