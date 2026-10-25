import Foundation
import SecretVault
import TokenVault
import VaultDomain

/// LoginRunner giả: ghi lại request, mô phỏng OAuthLoginService bằng cách ghi credential mới
/// vào repo (insert active + supersede cũ) rồi trả outcome dựng sẵn. `hook` chạy sau mỗi
/// bước để test kiểm tra bất biến trung gian (vd U4: luôn còn credential active).
public final class FakeLoginRunner: LoginRunner, @unchecked Sendable {
    /// NSLock + @unchecked Sendable — ngoại lệ Tests/.
    public typealias Simulate = @Sendable (LoginRequest) async throws -> LoginOutcome

    private let lock = NSLock()
    private var requestsValue: [LoginRequest] = []
    private var simulate: Simulate
    private var failure: Error?

    /// Chạy sau khi insert credential mới (trước supersede) và sau khi supersede.
    public var hook: (@Sendable (String) async -> Void)?

    public init(simulate: @escaping Simulate) {
        self.simulate = simulate
    }

    public var requests: [LoginRequest] {
        withLock { requestsValue }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func failNext(_ error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        failure = error
    }

    public func login(_ request: LoginRequest) async throws -> LoginOutcome {
        let shouldFail: Error? = withLock {
            requestsValue.append(request)
            let pending = failure
            if failure != nil { failure = nil }
            return pending
        }

        if let shouldFail {
            throw shouldFail
        }
        let outcome = try await simulate(request)
        if let hook {
            await hook("after-login")
        }
        return outcome
    }

    /// Mô phỏng chuẩn: tạo secret + credential mới active, supersede credential cũ.
    public static func standardSimulate(
        credentials: any CredentialRepository,
        secrets: SecretVault,
        ids: any IDGenerator,
        clock: any DateProvider
    ) -> Simulate {
        { request in
            guard case .existing(let account) = request.target else {
                throw DomainError.invariantViolated("FakeLoginRunner chỉ hỗ trợ .existing")
            }
            let previous = try await credentials.active(for: account)
            let secret = try await secrets.create(
                kind: .refreshToken, label: "rt mới", value: Data("rt-new".utf8), actor: .user)
            let credential = Credential(
                id: CredentialID(rawValue: ids.make()),
                accountId: account,
                refreshTokenRef: secret.id,
                requestedScopes: request.scopes,
                grantedScopes: request.scopes,
                issuedAt: clock.now(),
                status: .active)
            try await credentials.insert(credential)
            if let previous {
                try await credentials.markSuperseded(previous.id, by: credential.id)
            }
            let accountEntity = Account(
                id: account,
                providerId: .google,
                oauthClientId: request.oauthClientId,
                externalId: "sub-1",
                email: nil,
                displayName: nil,
                status: .healthy,
                statusChangedAt: clock.now(),
                createdAt: clock.now())
            return LoginOutcome(
                account: accountEntity,
                credential: credential,
                deniedScopes: [],
                isNewAccount: false)
        }
    }
}
