import Foundation
import HealthCheck

/// Sleeper giả: mỗi `sleep` đăng ký (deadline, continuation); test tiến thời gian ảo
/// bằng `advance(by:)` — sleep nào đến hạn được resume theo thứ tự.
public actor ManualSleeper: Sleeper {
    private var virtualNow: TimeInterval = 0
    private var waiters: [(deadline: TimeInterval, continuation: CheckedContinuation<Void, any Error>)] = []
    private var requestedValue: [TimeInterval] = []

    public init() {}

    /// Các khoảng sleep đã yêu cầu, theo thứ tự (assert backoff).
    public var requested: [TimeInterval] {
        requestedValue
    }

    public func sleep(for duration: Duration) async throws {
        let components = duration.components
        let seconds =
            TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        requestedValue.append(seconds)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            waiters.append((virtualNow + seconds, cont))
            drain()
        }
    }

    /// Test tiến thời gian ảo.
    public func advance(by seconds: TimeInterval) {
        virtualNow += seconds
        drain()
    }

    private func drain() {
        let due = waiters.filter { $0.deadline <= virtualNow }
        waiters.removeAll { $0.deadline <= virtualNow }
        for waiter in due {
            waiter.continuation.resume()
        }
    }
}
