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
        account = try? await runtime.accounts.get(accountId)
        credentials = (try? await runtime.credentials.list(for: accountId)) ?? []
        latestResult = try? await runtime.healthResults.latest(for: accountId)
        plan = try? await runtime.scopes.planGrantMore(accountId)
    }

    func runPrimary() async {
        switch primary {
        case .reauth:
            await reauth()
        case .grantMore:
            await grantMore()
        case .retry:
            _ = await runtime.scheduler.run(.manual(accountId))
            await load()
        case .fixClient, .openDetails, .none:
            break
        }
    }

    private func reauth() async {
        guard let account,
            let provider = try? await runtime.providers.provider(account.providerId)
        else { return }
        do {
            _ = try await runtime.scopes.execute(
                LoginRequest(
                    oauthClientId: account.oauthClientId,
                    scopes: provider.defaultScopes,
                    target: .existing(accountId)))
            await load()
        } catch let oauth as OAuthError where oauth == .userCancelled {
            self.error = "Đã hủy đăng nhập"
        } catch {
            self.error = "\(error)"
        }
    }

    private func grantMore() async {
        guard let plan else { return }
        switch plan {
        case .browser(let request):
            _ = try? await runtime.scopes.execute(request)
        case .consoleThenRelogin(_, _, let then):
            _ = try? await runtime.scopes.execute(then)
        case .nothingMissing:
            break
        }
        await load()
    }

    /// Thu hồi credential đang active.
    func revokeActive() async {
        guard let credential = try? await runtime.credentials.active(for: accountId) else {
            return
        }
        do {
            _ = try await runtime.scopes.revoke(
                credential.id, acknowledgeGrantWideRevocation: confirmWideRevocation)
            await load()
        } catch ScopeServiceError.grantWideRevocationNotAcknowledged {
            self.error = "Thu hồi Google sẽ đăng xuất MỌI tài khoản của app này — tick xác nhận để tiếp tục."
        } catch {
            self.error = "\(error)"
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
