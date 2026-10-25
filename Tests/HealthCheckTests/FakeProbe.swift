import Foundation
import KeyloftTestSupport
import Providers
import VaultDomain

/// Probe giả: trả kết quả/lỗi dựng sẵn, đếm số lần gọi, có thể trễ.
public final class FakeProbe: APIProbe, @unchecked Sendable {
    /// NSLock + @unchecked Sendable — ngoại lệ Tests/.
    private let lock = NSLock()
    private var result: ProbeResult
    private var failure: ProbeError?
    private var delayMs: Int = 0
    private var callsValue = 0

    public init(result: ProbeResult) {
        self.result = result
    }

    public static func ok(
        email: String? = "user@example.test", used: Int64 = 10, total: Int64? = 100,
        latencyMs: Int = 50
    ) -> FakeProbe {
        FakeProbe(
            result: ProbeResult(
                email: email, quota: Quota(used: used, total: total), latencyMs: latencyMs))
    }

    public var calls: Int {
        withLock { callsValue }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func fail(with error: ProbeError) {
        lock.lock()
        defer { lock.unlock() }
        failure = error
        result = ProbeResult(email: nil, quota: nil, latencyMs: 0)
    }

    public func setResult(_ newResult: ProbeResult) {
        lock.lock()
        defer { lock.unlock() }
        result = newResult
        failure = nil
    }

    public func setDelay(milliseconds: Int) {
        lock.lock()
        defer { lock.unlock() }
        delayMs = milliseconds
    }

    public func probe(accessToken: String) async throws -> ProbeResult {
        let current: (result: ProbeResult, failure: ProbeError?, delayMs: Int) = {
            lock.lock()
            defer { lock.unlock() }
            return (result, failure, delayMs)
        }()
        if current.delayMs > 0 {
            try await Task.sleep(for: .milliseconds(current.delayMs))
        }
        withLock { callsValue += 1 }
        if let error = current.failure {
            throw error
        }
        return current.result
    }
}
