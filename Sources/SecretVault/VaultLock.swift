import Foundation
import LocalAuthentication
import VaultDomain

public enum VaultLockState: Sendable, Equatable {
    case locked
    case unlocked(until: Date)
}

/// Bọc LAContext để vượt ranh giới actor. Ngoại lệ `@unchecked Sendable` duy nhất trong
/// Sources/: LAContext không Sendable nhưng object này bất biến sau khi tạo và chỉ được
/// đọc (không đột biến context sau khi chia sẻ) — chia sẻ an toàn giữa các actor.
public final class AuthenticatedContext: @unchecked Sendable {
    public let context: LAContext

    public init(context: LAContext) {
        self.context = context
    }
}

public protocol UserPresenceAuthenticator: Sendable {
    /// Hiện Touch ID / mật khẩu; trả context đã xác thực hoặc throw.
    func authenticate(reason: String) async throws -> AuthenticatedContext
}

/// Cổng khóa/mở khóa vault bằng Touch ID. Trạng thái unlocked tự hết hạn theo clock tiêm
/// (không cần timer — `state` tính lại mỗi lần đọc); App gọi `lock()` khi máy ngủ.
public actor VaultLock: KeychainAuthContextProvider {
    /// = LATouchIDAuthenticationMaximumAllowableReuseDuration.
    public static let reuseDuration: TimeInterval = 300

    private let authenticator: any UserPresenceAuthenticator
    private let clock: any DateProvider

    /// Hạn cuối context LAContext còn tái sử dụng được (không giãn bằng noteActivity).
    private var contextValidUntil: Date?
    /// Hạn hiện tại của trạng thái unlocked, luôn ≤ contextValidUntil.
    private var unlockedUntil: Date?
    private var current: AuthenticatedContext?
    private var continuations: [UUID: AsyncStream<VaultLockState>.Continuation] = [:]

    public init(authenticator: any UserPresenceAuthenticator, clock: any DateProvider) {
        self.authenticator = authenticator
        self.clock = clock
    }

    public nonisolated var state: VaultLockState {
        get async {
            await currentState()
        }
    }

    private func currentState() -> VaultLockState {
        if let until = unlockedUntil, clock.now() < until {
            return .unlocked(until: until)
        }
        return .locked
    }

    public func unlock(reason: String) async throws {
        let authenticated = try await authenticator.authenticate(reason: reason)
        let now = clock.now()
        let until = now.addingTimeInterval(Self.reuseDuration)
        contextValidUntil = until
        unlockedUntil = until
        current = authenticated
        publish(.unlocked(until: until))
    }

    public func lock() {
        contextValidUntil = nil
        unlockedUntil = nil
        current = nil
        publish(.locked)
    }

    /// Gia hạn idle timer, không vượt quá hạn tái sử dụng của context.
    public func noteActivity() {
        guard let validUntil = contextValidUntil else { return }
        let now = clock.now()
        guard now < validUntil else { return }
        let candidate = min(now.addingTimeInterval(Self.reuseDuration), validUntil)
        if candidate != unlockedUntil {
            unlockedUntil = candidate
            publish(.unlocked(until: candidate))
        }
    }

    /// Context còn hiệu lực cho KeychainSecretStore; nil nếu locked/quá hạn.
    public func currentContext() async -> AuthenticatedContext? {
        guard let until = unlockedUntil, clock.now() < until else { return nil }
        return current
    }

    /// Phát trạng thái hiện tại ngay khi subscribe, rồi mỗi lần đổi.
    public func states() -> AsyncStream<VaultLockState> {
        let (stream, continuation) = AsyncStream<VaultLockState>.makeStream()
        continuation.yield(currentState())
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func publish(_ state: VaultLockState) {
        for (id, continuation) in continuations {
            switch continuation.yield(state) {
            case .terminated: continuations[id] = nil
            case .dropped, .enqueued: break
            @unknown default: break
            }
        }
    }
}

/// LAContext.evaluatePolicy(.deviceOwnerAuthentication) — Touch ID rồi tới mật khẩu.
public struct LocalAuthenticationAuthenticator: UserPresenceAuthenticator {
    public init() {}

    public func authenticate(reason: String) async throws -> AuthenticatedContext {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = VaultLock.reuseDuration
        var evaluateError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluateError) else {
            throw SecretStoreError.authFailed
        }
        let (success, error) = await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: reason
            ) { ok, evaluationError in
                continuation.resume(returning: (ok, evaluationError as NSError?))
            }
        }
        guard success else {
            if let error, error.domain == LAError.errorDomain {
                let code = LAError.Code(rawValue: error.code) ?? .authenticationFailed
                if code == .userCancel {
                    throw SecretStoreError.userCanceled
                }
            }
            throw SecretStoreError.authFailed
        }
        return AuthenticatedContext(context: context)
    }
}
