import Foundation

/// Tham số OAuth trong callback (RFC 6749 §4.1.2 + RFC 9207 `iss`).
public struct CallbackParameters: Sendable, Equatable {
    public var code: String?
    public var state: String?
    public var iss: String?
    public var error: String?
    public var errorDescription: String?

    public init(
        code: String? = nil,
        state: String? = nil,
        iss: String? = nil,
        error: String? = nil,
        errorDescription: String? = nil
    ) {
        self.code = code
        self.state = state
        self.iss = iss
        self.error = error
        self.errorDescription = errorDescription
    }
}

/// Nhận callback OAuth trên redirect loopback (RFC 8252 §7.3).
public protocol CallbackReceiver: Sendable {
    /// Bắt đầu lắng nghe; trả về redirect URI thật (có port).
    func start() async throws -> URL
    func waitForCallback() async throws -> CallbackParameters
    func stop() async
}

public typealias CallbackReceiverFactory = @Sendable (_ configuredRedirect: URL) -> any CallbackReceiver
