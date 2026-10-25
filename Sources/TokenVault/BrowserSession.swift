import Foundation

public enum BrowserSessionError: Error, Sendable, Equatable {
    case userCancelled
    case failed(String)
}

/// Mở URL đăng nhập bằng trình duyệt hệ thống; trả về khi điều hướng tới `callbackScheme://`.
/// Impl thật (ASWebAuthenticationSession) nằm ở App (SPEC-011); TokenVault chỉ biết protocol.
public protocol BrowserSession: Sendable {
    func present(_ url: URL, callbackScheme: String) async throws
}
