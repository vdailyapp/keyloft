import Foundation
import Security
import Testing
import VaultDomain

@testable import SecretVault

@Suite("KeychainQuery")
struct KeychainQueryTests {
    @Test("U10: map OSStatus chuẩn")
    func mapStatuses() {
        #expect(KeychainQuery.map(-25300) == .notFound)
        #expect(KeychainQuery.map(-128) == .userCanceled)
        #expect(KeychainQuery.map(-25293) == .authFailed)
        #expect(KeychainQuery.map(-25308) == .interactionNotAllowed)
        #expect(KeychainQuery.map(-34018) == .missingEntitlement)
        #expect(KeychainQuery.map(-1) == .osStatus(-1))
    }

    @Test("Query base: đúng service/account, không sync, DP + access group theo config")
    func baseQuery() {
        let id = SecretID(rawValue: UUID())
        let ref = KeychainRef(kind: .refreshToken, id: id)

        let plain = KeychainQuery.base(
            for: ref, configuration: KeychainConfiguration(service: "svc.a"))
        #expect(plain[kSecClass as String] as? String == (kSecClassGenericPassword as String))
        #expect(plain[kSecAttrService as String] as? String == "svc.a")
        #expect(plain[kSecAttrAccount as String] as? String == ref.account)
        #expect((plain[kSecAttrSynchronizable as String] as? Bool) == false)
        #expect(plain[kSecUseDataProtectionKeychain as String] == nil)
        #expect(plain[kSecAttrAccessGroup as String] == nil)

        let signed = KeychainQuery.base(
            for: ref,
            configuration: KeychainConfiguration(
                service: "svc.b", accessGroup: "TEAM.app.vdaily.keyloft",
                useDataProtectionKeychain: true))
        #expect((signed[kSecUseDataProtectionKeychain as String] as? Bool) == true)
        #expect(signed[kSecAttrAccessGroup as String] as? String == "TEAM.app.vdaily.keyloft")
    }
}
