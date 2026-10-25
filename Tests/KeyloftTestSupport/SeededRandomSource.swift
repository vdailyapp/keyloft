import Foundation
import VaultDomain

/// Nguồn ngẫu nhiên tất định cho test: xorshift64 từ seed, hoặc lặp lại mảng bytes cố định.
/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class SeededRandomSource: RandomSource, @unchecked Sendable {
    private let lock = NSLock()
    private var state: UInt64
    private let fixed: Data?

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        fixed = nil
    }

    public init(fixed: Data) {
        state = 0
        self.fixed = fixed
    }

    public func bytes(count: Int) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let fixed else {
            return Self.xorshift(&state, count: count)
        }
        var data = Data(capacity: count)
        while data.count < count {
            data.append(fixed[data.count % fixed.count])
        }
        return data
    }

    private static func xorshift(_ state: inout UInt64, count: Int) -> Data {
        var data = Data(capacity: count)
        while data.count < count {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            var chunk = state.littleEndian
            withUnsafeBytes(of: &chunk) { data.append(contentsOf: $0) }
        }
        return data.prefix(count)
    }
}
