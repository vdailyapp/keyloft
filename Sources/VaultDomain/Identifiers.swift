import Foundation

/// ID của mọi entity: bọc UUID, encode Codable thành chuỗi UUID đơn (không phải object)
/// để DB/JSON lưu gọn và so sánh ổn định.
public protocol EntityID: Hashable, Codable, Sendable, CustomStringConvertible {
    var rawValue: UUID { get }
    init(rawValue: UUID)
}

extension EntityID {
    public var description: String { rawValue.uuidString.lowercased() }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "UUID không hợp lệ: \(raw)")
        }
        self.init(rawValue: uuid)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString.lowercased())
    }
}

public struct OAuthClientID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct AccountID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct CredentialID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct SecretID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct HealthCheckID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct AuditEventID: EntityID {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}
