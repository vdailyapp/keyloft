import Foundation
import TokenVault

/// CallbackReceiver giả cho test OAuthLoginService: trả tham số dựng sẵn sau `delay`.
public final class FakeCallbackReceiver: CallbackReceiver, @unchecked Sendable {
    /// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
    private let lock = NSLock()

    public var parameters: CallbackParameters
    public var redirect: URL = URL(string: "http://127.0.0.1:55555/callback")!
    public var delay: Duration = .zero

    private var startCountValue = 0
    private var stopCountValue = 0

    public init(parameters: CallbackParameters) {
        self.parameters = parameters
    }

    public var startCount: Int {
        withLock { startCountValue }
    }

    public var stopCount: Int {
        withLock { stopCountValue }
    }

    public func start() async throws -> URL {
        withLock {
            startCountValue += 1
            return redirect
        }
    }

    public func waitForCallback() async throws -> CallbackParameters {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return withLock { parameters }
    }

    public func stop() async {
        withLock { stopCountValue += 1 }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
