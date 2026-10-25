import Foundation
import KeyloftTestSupport
import LocalAuthentication
import SecretVault
import Testing
import VaultDomain

/// Authenticator giả: trả context dựng sẵn hoặc throw theo yêu cầu test.
final class FakeAuthenticator: UserPresenceAuthenticator, @unchecked Sendable {
    // NSLock + @unchecked Sendable — ngoại lệ Tests/.
    private let lock = NSLock()
    private var error: SecretStoreError?
    private(set) var reasons: [String] = []

    func failNext(with error: SecretStoreError) {
        lock.lock()
        defer { lock.unlock() }
        self.error = error
    }

    func authenticate(reason: String) async throws -> AuthenticatedContext {
        let failure = withLock {
            reasons.append(reason)
            return error
        }
        if let failure { throw failure }
        return AuthenticatedContext(context: LAContext())
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@Suite("VaultLock")
struct VaultLockTests {
    @Test("U11: unlock thành công → unlocked(until: now + 300)")
    func unlockSuccess() async throws {
        let clock = FixedDateProvider()
        let lock = VaultLock(authenticator: FakeAuthenticator(), clock: clock)

        try await lock.unlock(reason: "mở vault")
        #expect(await lock.state == .unlocked(until: clock.now().addingTimeInterval(300)))
    }

    @Test("U12: hết hạn tự khóa sau 301s; currentContext nil")
    func autoLock() async throws {
        let clock = FixedDateProvider()
        let lock = VaultLock(authenticator: FakeAuthenticator(), clock: clock)
        try await lock.unlock(reason: "mở")
        #expect(await lock.currentContext() != nil)

        clock.advance(by: 301)
        #expect(await lock.state == .locked)
        #expect(await lock.currentContext() == nil)
    }

    @Test("U13: authenticator hủy → state vẫn locked, lỗi truyền ra")
    func unlockCancelled() async throws {
        let authenticator = FakeAuthenticator()
        authenticator.failNext(with: .userCanceled)
        let lock = VaultLock(authenticator: authenticator, clock: FixedDateProvider())

        do {
            try await lock.unlock(reason: "mở")
            Issue.record("phải throw userCanceled")
        } catch let error as SecretStoreError {
            #expect(error == .userCanceled)
        }
        #expect(await lock.state == .locked)
        #expect(await lock.currentContext() == nil)
    }

    @Test("U14: states() phát [locked, unlocked, locked]; ban đầu + sau mỗi đổi")
    func stateStream() async throws {
        let clock = FixedDateProvider()
        let lock = VaultLock(authenticator: FakeAuthenticator(), clock: clock)
        var iterator = await lock.states().makeAsyncIterator()

        try await lock.unlock(reason: "mở")
        await lock.lock()

        var received: [VaultLockState] = []
        for _ in 0..<3 {
            if let state = await iterator.next() {
                received.append(state)
            }
        }
        #expect(received[0] == .locked)
        guard case .unlocked = received[1] else {
            Issue.record("kỳ vọng unlocked, được \(received[1])")
            return
        }
        #expect(received[2] == .locked)
    }

    @Test("noteActivity giãn hạn nhưng không vượt hạn context")
    func noteActivityCapped() async throws {
        let clock = FixedDateProvider()
        let lock = VaultLock(authenticator: FakeAuthenticator(), clock: clock)
        try await lock.unlock(reason: "mở")

        clock.advance(by: 100)
        await lock.noteActivity()
        // cap = now(100) + 300 = 400 > contextValidUntil(300) → giữ 300.
        #expect(await lock.state == .unlocked(until: clock.now().addingTimeInterval(200)))

        clock.advance(by: 100)
        await lock.noteActivity()
        // vẫn cap tại contextValidUntil = epoch + 300 (= now + 100).
        #expect(await lock.state == .unlocked(until: clock.now().addingTimeInterval(100)))
    }
}
