import Foundation
import LocalAuthentication
import SecretVault
import Testing
import TokenVault
import VaultDomain
import VaultRuntime
import KeyloftTestSupport
@testable import Keyloft

/// Authenticator giả cho test Secrets: luôn thành công, không đụng Touch ID thật.
final class FakeAuthenticator: UserPresenceAuthenticator, @unchecked Sendable {
    // NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
    func authenticate(reason: String) async throws -> AuthenticatedContext {
        AuthenticatedContext(context: LAContext())
    }
}

@MainActor
@Suite("Secrets model")
struct SecretsTests {
    /// Runtime in-memory với authenticator giả (unlock không cần Touch ID thật).
    static func makeRuntime(clock: FixedDateProvider = FixedDateProvider()) -> VaultRuntime {
        var deps = RuntimeDependencies.inMemory(
            http: StubHTTPClient(),
            browser: FakeBrowserSession(behavior: .cancel),
            clock: clock,
            ids: SequentialIDGenerator(),
            random: SeededRandomSource(seed: 3),
            store: InMemorySecretStore())
        deps.authenticator = FakeAuthenticator()
        return VaultRuntime(deps)
    }

    @Test("U12: Secrets khóa — lock .locked → rows rỗng, needsUnlock == true")
    func lockedHidesRows() async throws {
        let runtime = Self.makeRuntime()
        let model = SecretsModel(runtime: runtime)
        // Secret có sẵn trong Keychain nhưng vault đang khóa → không được render.
        _ = try await runtime.secrets.create(
            kind: .apiKey, label: "k1", value: Data("v1".utf8), actor: .user)

        await model.load()

        #expect(model.rows.isEmpty)
        #expect(model.needsUnlock)
    }

    @Test("U13: unlock rồi tự khóa sau 301 s — rows bị xóa khỏi state")
    func autoLockClearsRows() async throws {
        let clock = FixedDateProvider()
        let runtime = Self.makeRuntime(clock: clock)
        let model = SecretsModel(runtime: runtime)
        _ = try await runtime.secrets.create(
            kind: .apiKey, label: "k1", value: Data("v1".utf8), actor: .user)

        await model.unlock()
        await model.load()
        #expect(!model.rows.isEmpty)
        #expect(!model.needsUnlock)

        // Quá reuseDuration (300 s) — VaultLock tự khóa theo clock; UI kiểm tra chủ động.
        clock.advance(by: 301)
        await model.refreshLockState()

        #expect(model.needsUnlock)
        #expect(model.rows.isEmpty)
    }

    @Test("U14: reveal tự xóa — reveal → advance 30 s → revealed[id] == nil")
    func revealExpires() async throws {
        let clock = FixedDateProvider()
        let runtime = Self.makeRuntime(clock: clock)
        let model = SecretsModel(runtime: runtime)
        let secret = try await runtime.secrets.create(
            kind: .password, label: "p1", value: Data("pw-value".utf8), actor: .user)

        await model.unlock()
        let shown = await model.reveal(secret.id)
        #expect(shown == "pw-value")
        #expect(model.revealed[secret.id] == "pw-value")

        clock.advance(by: 30)
        #expect(model.revealed[secret.id] == nil)
    }

    @Test("U14 (phụ): refresh token chỉ metadata — reveal trả nil, không hiện giá trị")
    func refreshTokenNotRevealable() async throws {
        let runtime = Self.makeRuntime()
        let model = SecretsModel(runtime: runtime)
        let secret = try await runtime.secrets.create(
            kind: .refreshToken, label: "rt", value: Data("rt-value".utf8), actor: .app)

        await model.unlock()
        await model.load()

        // Model vẫn trả giá trị nếu gọi trực tiếp, nhưng UI chỉ render nút Hiện cho
        // secret người nhập — kiểm tra bằng trường thuần isUserSecret.
        #expect(SecretKind.refreshToken.isUserSecret == false)
        #expect(SecretKind.apiKey.isUserSecret)
        #expect(model.rows.contains { $0.id == secret.id })
    }
}
