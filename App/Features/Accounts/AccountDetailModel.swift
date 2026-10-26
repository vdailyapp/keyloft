import Foundation
import Observation
import TokenVault
import VaultDomain
import VaultRuntime

@MainActor
@Observable
final class AccountDetailModel {
    private(set) var account: Account?
    private(set) var credentials: [Credential] = []
    private(set) var latestResult: HealthCheckResult?
    private(set) var plan: GrantMorePlan?
    private(set) var error: String?
    private(set) var confirmWideRevocation = false

    private let runtime: VaultRuntime
    let accountId: AccountID

    init(runtime: VaultRuntime, accountId: AccountID) {
        self.runtime = runtime
        self.accountId = accountId
    }

    var primary: PrimaryAction {
        guard let account else { return .none }
        return primaryAction(for: account, latest: latestResult, plan: plan)
    }

    func load() async {
        error = nil
        do {
            account = try await runtime.accounts.get(accountId)
            credentials = try await runtime.credentials.list(for: accountId)
            latestResult = try await runtime.healthResults.latest(for: accountId)
            plan = try await runtime.scopes.planGrantMore(accountId)
        } catch {
            self.error = "\(error)"
        }
    }

    func runPrimary() async {
        switch primary {
        case .reauth:
            await reauth()
        case .grantMore:
            await grantMore()
        case .retry:
            await checkNow()
        case .fixClient, .openDetails, .none:
            break
        }
    }

    /// "Check now" — lỗi run của scheduler hiện cho người dùng, không nuốt.
    func checkNow() async {
        do {
            _ = try await runtime.scheduler.run(.manual(accountId))
        } catch {
            await load()  // load() xóa error — gán lỗi SAU load
            self.error = "\(error)"
            return
        }
        await load()
    }

    private func reauth() async {
        guard let account else { return }
        do {
            let provider = try await runtime.providers.provider(account.providerId)
            _ = try await runtime.scopes.execute(
                LoginRequest(
                    oauthClientId: account.oauthClientId,
                    scopes: provider.defaultScopes,
                    target: .existing(accountId)))
            await load()
        } catch {
            await load()  // load() xóa error — gán lỗi SAU load
            self.error = oauthErrorMessage(error)
        }
    }

    private func grantMore() async {
        guard let plan else { return }
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

    /// Thu hồi credential đang active.
    func revokeActive() async {
        do {
            guard let credential = try await runtime.credentials.active(for: accountId) else {
                return
            }
            _ = try await runtime.scopes.revoke(
                credential.id, acknowledgeGrantWideRevocation: confirmWideRevocation)
            await load()
        } catch ScopeServiceError.grantWideRevocationNotAcknowledged {
            self.error = "Thu hồi Google sẽ đăng xuất MỌI tài khoản của app này — tick xác nhận để tiếp tục."
        } catch {
            self.error = oauthErrorMessage(error)
        }
    }

    func remove(ack: Bool) async {
        do {
            _ = try await runtime.scopes.removeAccount(
                accountId, acknowledgeGrantWideRevocation: ack)
        } catch ScopeServiceError.grantWideRevocationNotAcknowledged {
            confirmWideRevocation = true
        } catch {
            self.error = "\(error)"
        }
    }
}
