import Foundation
import TokenVault

/// BrowserSession cho CLI: không tự mở trình duyệt — người dùng phải đăng nhập trong app
/// (thông điệp hướng dẫn do lớp CLI in khi bắt lỗi).
public struct UnavailableBrowserSession: BrowserSession {
    public init() {}

    public func present(_ url: URL, callbackScheme: String) async throws {
        throw OAuthError.userCancelled
    }
}
