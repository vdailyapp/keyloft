import Foundation
import LocalAuthentication
import Security
import Testing
import VaultDomain

@testable import SecretVault

/// Test Keychain THẬT — chỉ chạy với `make test-keychain` (login keychain, service riêng,
/// tự dọn). Không đụng dữ liệu thật của người dùng.
///
/// Hạn chế nền tảng (xác nhận thực nghiệm 2026-10-25): binary chưa ký chạy `swift test`
/// không tạo được item có SecAccessControl (errSecMissingEntitlement -34018) và login
/// keychain không trả về thuộc tính accessible/synchronizable. I3/I4 chỉ chạy khi môi
/// trường hỗ trợ (app đã ký + Data Protection Keychain — kiểm lại ở SPEC-011/T29).
@Suite("KeychainSecretStore thật")
struct SecretVaultKeychainTests {
    static let enabled = ProcessInfo.processInfo.environment["KEYLOFT_KEYCHAIN_TESTS"] == "1"

    /// Thử tạo 1 item access-control trong service test; -34018 → môi trường không hỗ trợ.
    static let presenceSupported: Bool = {
        let probe = KeychainConfiguration(
            service: "app.vdaily.keyloft.tests.probe.\(UUID().uuidString)",
            useDataProtectionKeychain: false)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probe.service,
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data("x".utf8),
        ]
        var error: Unmanaged<CFError>?
        guard
            let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error)
        else { return false }
        query[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(query as CFDictionary, nil)
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: probe.service,
            ] as CFDictionary)
        return status == errSecSuccess
    }()

    struct LockedContextProvider: KeychainAuthContextProvider {
        func currentContext() async -> AuthenticatedContext? {
            let context = LAContext()
            context.interactionNotAllowed = true
            return AuthenticatedContext(context: context)
        }
    }

    let configuration = KeychainConfiguration(
        service: "app.vdaily.keyloft.tests.\(UUID().uuidString)",
        useDataProtectionKeychain: false)

    /// Xóa toàn bộ item của service test này.
    func cleanup() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    @Test("I1: item AfterFirstUnlockThisDeviceOnly, không sync", .enabled(if: Self.enabled))
    func itemAttributes() async throws {
        let store = KeychainSecretStore(configuration: configuration)
        let ref = KeychainRef(kind: .refreshToken, id: SecretID(rawValue: UUID()))
        defer { cleanup() }

        try await store.set(Data("v".utf8), for: ref, policy: .afterFirstUnlock)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
            kSecAttrAccount as String: ref.account,
            kSecReturnAttributes as String: true,
        ]
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #expect(status == errSecSuccess)
        // Login keychain chỉ trả metadata cơ bản; accessible/synchronizable được bảo đảm
        // bởi cấu trúc query lúc ADD (xem KeychainQueryTests) và chỉ đọc lại được trong
        // Data Protection Keychain của app đã ký.
        let attrs = result as? [String: Any]
        #expect((attrs?[kSecClass as String] as? String) == (kSecClassGenericPassword as String))
        #expect((attrs?[kSecAttrAccount as String] as? String) == ref.account)
    }

    @Test("I2: set/get/overwrite/delete; delete lần 2 không lỗi", .enabled(if: Self.enabled))
    func lifecycle() async throws {
        let store = KeychainSecretStore(configuration: configuration)
        let ref = KeychainRef(kind: .clientSecret, id: SecretID(rawValue: UUID()))
        defer { cleanup() }

        try await store.set(Data("a".utf8), for: ref, policy: .afterFirstUnlock)
        try await store.set(Data("b".utf8), for: ref, policy: .afterFirstUnlock)
        let value = try await store.get(ref, reason: "test")
        #expect(String(decoding: value, as: UTF8.self) == "b")

        try await store.delete(ref)
        do {
            _ = try await store.get(ref, reason: "test")
            Issue.record("get sau delete phải notFound")
        } catch let error as SecretStoreError {
            #expect(error == .notFound)
        }
        try await store.delete(ref)
    }

    @Test("I3: contains item presence không hiện UI", .enabled(if: Self.enabled && Self.presenceSupported))
    func containsWithoutUI() async throws {
        let store = KeychainSecretStore(configuration: configuration)
        let ref = KeychainRef(kind: .apiKey, id: SecretID(rawValue: UUID()))
        defer { cleanup() }

        try await store.set(Data("k".utf8), for: ref, policy: .userPresence)
        let exists = try await store.contains(ref)
        #expect(exists)
    }

    @Test(
        "I4: get item presence khi máy khóa → interactionNotAllowed",
        .enabled(if: Self.enabled && Self.presenceSupported))
    func getPresenceWhileLocked() async throws {
        let store = KeychainSecretStore(
            configuration: configuration, contextProvider: LockedContextProvider())
        let ref = KeychainRef(kind: .password, id: SecretID(rawValue: UUID()))
        defer { cleanup() }

        try await store.set(Data("p".utf8), for: ref, policy: .userPresence)
        await #expect(throws: SecretStoreError.interactionNotAllowed) {
            _ = try await store.get(ref, reason: "đọc khi khóa")
        }
    }
}
