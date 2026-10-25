import Foundation

public enum PersistenceError: Error, Sendable, Equatable {
    /// DB có migration mới hơn code biết (vd mở bằng app cũ).
    case schemaTooNew
    /// Lỗi GRDB bọc lại, kèm message (đã làm sạch, không chứa dữ liệu).
    case database(String)
    /// Decode JSON/enum của một hàng thất bại.
    case corruptRow(table: String, id: String)
}
