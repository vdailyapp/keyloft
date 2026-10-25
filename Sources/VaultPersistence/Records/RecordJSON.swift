import Foundation

/// Mã hóa cột JSON (ScopeSet, [HealthCheckItem], AuditResult) —dùng thống nhất JSONEncoder/Decoder chuẩn.
enum RecordJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(string.utf8))
    }
}
