import Foundation

/// Seam để ScopeService gọi đăng nhập mà không phụ thuộc cứng OAuthLoginService
/// (test dùng FakeLoginRunner). Mọi login từ UI đi qua ScopeService.execute.
public protocol LoginRunner: Sendable {
    func login(_ request: LoginRequest) async throws -> LoginOutcome
}

extension OAuthLoginService: LoginRunner {}
