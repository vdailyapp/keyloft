import Foundation

/// Tập scope OAuth: case-sensitive (RFC 6749), trim khoảng trắng, bỏ phần tử rỗng.
/// Codable encode thành mảng đã sắp xếp để ổn định khi lưu DB/JSON.
public struct ScopeSet: Hashable, Codable, Sendable, ExpressibleByArrayLiteral, CustomStringConvertible {
    public private(set) var values: Set<String>

    public init(_ values: some Sequence<String>) {
        var set = Set<String>()
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { set.insert(trimmed) }
        }
        self.values = set
    }

    /// Tách theo bất kỳ loại whitespace nào (RFC 6749 §3.3 dùng dấu cách).
    public init(spaceDelimited: String) {
        self.init(spaceDelimited.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    }

    public init(arrayLiteral elements: String...) {
        self.init(elements)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([String].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values.sorted())
    }

    /// Sorted, nối bằng " " — dạng đưa vào request OAuth.
    public var spaceDelimited: String { values.sorted().joined(separator: " ") }
    public var isEmpty: Bool { values.isEmpty }
    public var count: Int { values.count }

    public func contains(_ scope: String) -> Bool { values.contains(scope) }
    public func union(_ other: ScopeSet) -> ScopeSet { ScopeSet(values.union(other.values)) }
    public func subtracting(_ other: ScopeSet) -> ScopeSet { ScopeSet(values.subtracting(other.values)) }
    public func isSuperset(of other: ScopeSet) -> Bool { values.isSuperset(of: other.values) }

    /// Scope trong self (đang cần) mà `granted` không có.
    public func missing(in granted: ScopeSet) -> ScopeSet { subtracting(granted) }

    public var description: String { spaceDelimited }
}
