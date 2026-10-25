import Foundation
import VaultDomain

/// UUID tăng dần dạng 00000000-0000-0000-0000-00000000000N — dễ đọc khi assert thứ tự.
/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class SequentialIDGenerator: IDGenerator, @unchecked Sendable {
    private let lock = NSLock()
    private var count: UInt64 = 0

    public init() {}

    public func make() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llu", count))!
    }
}
