import Foundation

/// Seam cho `Task.sleep` — test dùng ManualSleeper điều khiển thời gian.
public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
