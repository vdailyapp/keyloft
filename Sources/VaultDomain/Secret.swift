import Foundation

/// Con trỏ tới item Keychain: service cố định + account "<kind>.<secret-uuid>".
/// Giá trị bí mật thật chỉ nằm trong Keychain; DB chỉ lưu ref này.
public struct KeychainRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public static let service = "app.vdaily.keyloft"
    public let account: String

    public init(kind: SecretKind, id: SecretID) {
        self.account = "\(kind.rawValue).\(id.rawValue.uuidString.lowercased())"
    }

    public var description: String { "\(Self.service)/\(account)" }
}

/// Metadata của secret trong Keychain — không bao giờ chứa giá trị.
public struct Secret: Codable, Sendable, Equatable, Identifiable {
    public let id: SecretID
    public var kind: SecretKind
    public var label: String
    public var keychainRef: KeychainRef
    public var requiresUserPresence: Bool
    public var createdAt: Date
    public var rotatedAt: Date?

    public init(
        id: SecretID,
        kind: SecretKind,
        label: String,
        keychainRef: KeychainRef,
        requiresUserPresence: Bool,
        createdAt: Date,
        rotatedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.keychainRef = keychainRef
        self.requiresUserPresence = requiresUserPresence
        self.createdAt = createdAt
        self.rotatedAt = rotatedAt
    }
}
