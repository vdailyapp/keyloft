import Foundation

public enum DomainError: Error, Sendable, Equatable {
    /// Entity không tồn tại, vd "account:<id>".
    case notFound(String)
    /// Xóa entity còn quan hệ phụ thuộc, vd "oauth_client:<id>".
    case hasDependents(String)
    case randomUnavailable
    case invariantViolated(String)
}
