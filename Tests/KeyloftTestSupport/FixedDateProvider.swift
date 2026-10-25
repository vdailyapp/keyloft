import Foundation
import VaultDomain

/// Đồng hồ giả cho test: `now()` trả thời điểm hiện tại của fake, dịch chuyển bằng `advance`.
/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class FixedDateProvider: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ date: Date = Date(timeIntervalSince1970: 1_761_353_600)) {
        current = date
    }

    public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }

    public func set(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        current = date
    }
}
