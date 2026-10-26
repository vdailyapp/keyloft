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
        } catch {
            self.error = oauthErrorMessage(error)
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
        do {
            guard let account = try await runtime.accounts.get(accountId) else { return }
            let provider = try await runtime.providers.provider(account.providerId)
            _ = try await addOrReauth(account: account, scopes: provider.defaultScopes)
        } catch {
            await load()  // load() xóa error — gán lỗi SAU load
            self.error = oauthErrorMessage(error)
            return
        }
        await load()
    }

    private func grantMore(_ accountId: AccountID, plan: GrantMorePlan) async {
        do {
            switch plan {
            case .browser(let request), .consoleThenRelogin(_, _, let request):
                _ = try await runtime.scopes.execute(request)
            case .nothingMissing:
                break
            }
        } catch {
            await load()  // load() xóa error — gán lỗi SAU load
            self.error = oauthErrorMessage(error)
            return
        }
        await load()
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
            if !ack, let account = try await runtime.accounts.get(accountId) {
                // Không được bỏ qua bước xác nhận khi tra cứu provider lỗi — Google revoke
                // cả grant phải có ack tường minh.
                let provider = try await runtime.providers.provider(account.providerId)
                if case .rfc7009(_, true) = provider.quirks.revocation {
                    pendingConfirmation = .grantWideRevocation(accountId)
                    return
                }
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
            do {
                let clients = try await runtime.clients.list(provider: nil)
                var grouped: [ProviderID: [OAuthClient]] = [:]
                for client in clients {
                    grouped[client.providerId, default: []].append(client)
                }
                return ProviderID.allCases.compactMap { provider in
                    guard let list = grouped[provider], !list.isEmpty else { return nil }
                    return (provider, list)
                }
            } catch {
                self.error = "\(error)"
                return []
            }
        }
    }
}

/// Map lỗi sang chuỗi hiển thị cho người dùng — dùng chung cho add/relogin/grantMore
/// và model chi tiết; lỗi hủy từ luồng OAuth hiện câu thân thiện, còn lại hiện mô tả.
func oauthErrorMessage(_ error: Error) -> String {
    // Đối chiếu hủy qua mô tả case: hosted-test nhân bản metadata kiểu giữa bundle app
    // và bundle test làm `as?` thất bại; mô tả case cho kết quả nhất quán mọi môi trường.
    if String(describing: error) == "userCancelled" {
        return "Đã hủy đăng nhập"
    }
    return switch error {
    case let oauth as OAuthError:
        "Đăng nhập thất bại: \(oauth)"
    default:
        "\(error)"
    }
}
