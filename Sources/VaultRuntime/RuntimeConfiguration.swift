import Foundation
import HealthCheck
import SecretVault

public enum RuntimeContext: Sendable {
    case app
    case cli
}

public enum RuntimeError: Error, Sendable, Equatable {
    /// CLI không tạo DB — chạy app trước để khởi tạo vault.
    case vaultNotInitialized
    /// Keychain không dùng được (thường là build chưa ký); kèm gợi ý.
    case keychainUnavailable(hint: String)
}

public struct RuntimeConfiguration: Sendable {
    public var databaseURL: URL
    public var keychain: KeychainConfiguration
    public var healthPolicy: HealthPolicy

    public init(
        databaseURL: URL, keychain: KeychainConfiguration, healthPolicy: HealthPolicy
    ) {
        self.databaseURL = databaseURL
        self.keychain = keychain
        self.healthPolicy = healthPolicy
    }

    /// app: Data Protection Keychain; cli: giống app, trừ khi KEYLOFT_DEV_LOGIN_KEYCHAIN=1
    /// (build dev chưa ký → login keychain để test).
    public static func `default`(
        for context: RuntimeContext,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> RuntimeConfiguration {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        let directory = support.appendingPathComponent("app.vdaily.keyloft", isDirectory: true)
        let devLoginKeychain = environment["KEYLOFT_DEV_LOGIN_KEYCHAIN"] == "1"
        return RuntimeConfiguration(
            databaseURL: directory.appendingPathComponent("vault.sqlite"),
            keychain: KeychainConfiguration(
                useDataProtectionKeychain: !devLoginKeychain),
            healthPolicy: HealthPolicy())
    }
}
