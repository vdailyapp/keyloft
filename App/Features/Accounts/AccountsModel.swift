import Foundation
import Observation
import TokenVault
import VaultDomain
import VaultRuntime

struct AccountRow: Identifiable, Equatable {
    let id: AccountID
    let provider: ProviderID
    let email: String?
    let displayName: String?
    var status: AccountStatus
    var needsReauth: Bool
}

enum PendingConfirmation: Equatable {
    case grantWideRevocation(AccountID)
}

@MainActor
@Observable
final class AccountsModel {
    private(set) var rows: [AccountRow] = []
    private(set) var error: String?
    private(set) var pendingConfirmation: PendingConfirmation?
    private(set) var adding = false
    /// Debug/test: chuỗi mô tả lỗi gốc (không chứa dữ liệu nhạy cảm).
    private(set) var rawErrorForTest: String?

    private let runtime: VaultRuntime
    private var observer: Task<Void, Never>?

    init(runtime: VaultRuntime) {
        self.runtime = runtime
    }

    func load() async {
        error = nil
        do {
            let accounts = try await runtime.accounts.list()
            rows = accounts.map { account in
                AccountRow(
                    id: account.id,
                    provider: account.providerId,
                    email: account.email,
                    displayName: account.displayName,
                    status: account.status,
                    needsReauth: account.status == .needsReauth)
            }
        } catch {
            self.error = "\(error)"
        }
    }

    func observeUpdates() {
        observer?.cancel()
        observer = Task { [weak self] in
            guard let updates = await self?.runtime.scheduler.updates else { return }
            for await result in updates {
                await MainActor.run {
                    self?.apply(result)
                }
            }
        }
    }

    /// Áp kết quả check mới (cũng dùng bởi test mô phỏng scheduler.updates).
    func apply(_ result: HealthCheckResult) {
        if let index = rows.firstIndex(where: { $0.id == result.accountId }) {
            rows[index].status = result.status
            rows[index].needsReauth = result.status == .needsReauth
        }
    }

    func stopObserving() {
        observer?.cancel()
        observer = nil
    }

    /// Thêm account: mọi login đi qua ScopeService (SPEC-009).
    func add(provider: ProviderID, client: OAuthClientID) async {
        adding = true
        defer { adding = false }
        error = nil
        do {
            let providerEntity = try await runtime.providers.provider(provider)
            _ = try await runtime.scopes.execute(
                LoginRequest(
                    oauthClientId: client,
                    scopes: providerEntity.defaultScopes,
                    target: .newAccount))
            await load()  // load() xóa error — chỉ gọi khi thành công
        } catch let oauthError as OAuthError {
            rawErrorForTest = String(describing: oauthError)
            switch oauthError {
            case .userCancelled:
                self.error = "Đã hủy đăng nhập"
                print("ADD-MODEL-DEBUG assigned error, now=\(self.error ?? "nil")")
            default:
                self.error = "Đăng nhập thất bại: \(oauthError)"
            }
        } catch let browserError as BrowserSessionError {
            rawErrorForTest = String(describing: browserError)
            self.error = browserError == .userCancelled ? "Đã hủy đăng nhập" : "\(browserError)"
        } catch {
            rawErrorForTest = String(describing: error)
            self.error = "\(error)"
        }
    }

    func perform(_ action: PrimaryAction, on accountId: AccountID) async {
        switch action {
        case .reauth:
            await relogin(accountId)
        case .grantMore(let plan):
            await grantMore(accountId, plan: plan)
        case .retry, .openDetails, .none:
            break
        case .fixClient:
            break
        }
    }

    private func relogin(_ accountId: AccountID) async {
        guard let account = try? await runtime.accounts.get(accountId),
            let provider = try? await runtime.providers.provider(account.providerId)
        else { return }
        _ = try? await addOrReauth(account: account, scopes: provider.defaultScopes)
        await load()
    }

    private func grantMore(_ accountId: AccountID, plan: GrantMorePlan) async {
        switch plan {
        case .browser(let request):
            _ = try? await runtime.scopes.execute(request)
            await load()
        case .consoleThenRelogin(_, _, let then):
            _ = try? await runtime.scopes.execute(then)
            await load()
        case .nothingMissing:
            break
        }
    }

    private func addOrReauth(account: Account, scopes: ScopeSet) async throws -> LoginOutcome {
        try await runtime.scopes.execute(
            LoginRequest(
                oauthClientId: account.oauthClientId,
                scopes: scopes,
                target: .existing(account.id)))
    }

    /// Xóa account; Google cần xác nhận thu hồi cả grant.
    func remove(_ accountId: AccountID, ack: Bool) async {
        pendingConfirmation = nil
        do {
            if !ack, let account = try await runtime.accounts.get(accountId),
                let provider = try? await runtime.providers.provider(account.providerId),
                case .rfc7009(_, true) = provider.quirks.revocation
            {
                pendingConfirmation = .grantWideRevocation(accountId)
                return
            }
            _ = try await runtime.scopes.removeAccount(
                accountId, acknowledgeGrantWideRevocation: ack)
            await load()
        } catch {
            self.error = "\(error)"
        }
    }

    var clientsForAdd: [(ProviderID, [OAuthClient])] {
        get async {
            let clients = (try? await runtime.clients.list(provider: nil)) ?? []
            var grouped: [ProviderID: [OAuthClient]] = [:]
            for client in clients {
                grouped[client.providerId, default: []].append(client)
            }
            return ProviderID.allCases.compactMap { provider in
                guard let list = grouped[provider], !list.isEmpty else { return nil }
                return (provider, list)
            }
        }
    }
}
