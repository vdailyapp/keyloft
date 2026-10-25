import Foundation
import HealthCheck
import Observation
import SecretVault
import TokenVault
import VaultDomain
import VaultRuntime

/// Giữ VaultRuntime + vòng đời app: scheduler (trigger ngoài app mở/máy thức), khóa vault
/// khi máy ngủ/đổi session, cập nhật latestStatuses cho UI từ scheduler.updates.
@MainActor
@Observable
final class AppContainer {
    let runtime: VaultRuntime
    private(set) var latestStatuses: [AccountID: AccountStatus] = [:]
    var lockState: VaultLockState = .locked

    private var triggerContinuation: AsyncStream<HealthTrigger>.Continuation?
    private var lifecycleTasks: [Task<Void, Never>] = []
    private let notifier = Notifier()

    init() throws {
        runtime = try VaultRuntime.live(context: .app, browser: WebAuthBrowserSession())
    }

    /// Dùng cho test/preview khi không muốn mở vault thật.
    init(runtime: VaultRuntime) {
        self.runtime = runtime
    }

    func start() {
        let (stream, continuation) = AsyncStream<HealthTrigger>.makeStream()
        triggerContinuation = continuation

        Task {
            await runtime.scheduler.start(external: stream)
        }
        continuation.yield(.appLaunch)

        // Menu bar/UI nhận kết quả check mới nhất.
        lifecycleTasks.append(
            Task { [weak self] in
                guard let updates = await self?.runtime.scheduler.updates else { return }
                for await result in updates {
                    await MainActor.run {
                        self?.applyStatus(result)
                    }
                }
            })

        // Khóa vault theo sự kiện hệ thống; máy thức → check lại.
        let events = SystemEvents(
            onWake: { [weak self] in
                self?.triggerContinuation?.yield(.wake)
            },
            onLock: { [weak self] in
                Task { await self?.runtime.lock.lock() }
            })
        lifecycleTasks.append(contentsOf: events.start())

        // Theo dõi trạng thái khóa cho UI.
        lifecycleTasks.append(
            Task { [weak self] in
                guard let states = await self?.runtime.lock.states() else { return }
                for await state in states {
                    await MainActor.run {
                        self?.lockState = state
                    }
                }
            })

        Task { await notifier.requestAuthorization() }
    }

    func stop() {
        triggerContinuation?.finish()
        triggerContinuation = nil
        lifecycleTasks.forEach { $0.cancel() }
        lifecycleTasks.removeAll()
        Task { await runtime.scheduler.stop() }
    }

    /// Test/preview đẩy trigger.
    func sendTrigger(_ trigger: HealthTrigger) {
        triggerContinuation?.yield(trigger)
    }

    #if DEBUG
    /// Luồng thật qua OAuthLoginService — dùng để chứng minh login end-to-end trước khi
    /// có UI đầy đủ (T26). Tạo OAuthClient nhập tay rồi login Google.
    func debugAddGoogleAccount(clientId: String) async -> String {
        guard !clientId.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Cần nhập Client ID"
        }
        do {
            let client = OAuthClient(
                id: OAuthClientID(rawValue: UUID()),
                providerId: .google,
                clientId: clientId.trimmingCharacters(in: .whitespaces),
                clientSecretRef: nil,
                redirectURI: URL(string: "http://127.0.0.1/callback")!,
                label: "Debug Google",
                createdAt: runtime.clock.now())
            try await runtime.clients.save(client)
            let outcome = try await runtime.scopes.execute(
                LoginRequest(
                    oauthClientId: client.id,
                    scopes: [
                        "openid", "email", "https://www.googleapis.com/auth/drive",
                    ],
                    target: .newAccount))
            return "OK: \(outcome.account.email ?? outcome.account.externalId) — \(outcome.account.status.rawValue)"
        } catch {
            return "Lỗi: \(error)"
        }
    }
    #endif

    private func applyStatus(_ result: HealthCheckResult) {
        let previous = latestStatuses[result.accountId]
        latestStatuses[result.accountId] = result.status
        guard previous != nil, previous != result.status else { return }
        Task { [notifier] in
            if let account = try? await runtime.accounts.get(result.accountId), let old = previous {
                await notifier.statusChanged(account: account, from: old, to: result.status)
            }
        }
    }
}
