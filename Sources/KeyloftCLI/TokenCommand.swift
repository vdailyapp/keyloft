import ArgumentParser
import Foundation
import TokenVault
import VaultDomain
import VaultRuntime

struct TokenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "token",
        abstract: "In access token của account ra stdout")

    @Argument(help: "Account (UUID, tiền tố ≥ 4, email, hoặc provider:email)")
    var account: String

    @Option(name: .long, help: "Token còn hạn tối thiểu bao nhiêu giây")
    var minValidity: Int = 60

    @Flag(name: .long, help: "Bỏ qua cache, refresh luôn")
    var force = false

    func run() async throws {
        do {
            let runtime = try Keyloft.makeRuntime()
            let accounts = try await runtime.accounts.list()
            let target: Account
            switch AccountSelector.resolve(account, in: accounts) {
            case .success(let match):
                target = match
            case .failure(let error):
                Keyloft.streams.writeStderr(AccountsCommand.describe(error))
                throw ExitCode(KeyloftExitCode.usage.rawValue)
            }

            let token: AccessToken
            if force {
                token = try await runtime.tokens.forceRefresh(for: target.id)
            } else {
                token = try await runtime.tokens.accessToken(
                    for: target.id, minValidity: TimeInterval(minValidity))
            }
            // Audit TRƯỚC khi in token (SPEC-010 §2); mọi giá trị đi qua provider chuẩn.
            try await runtime.audit.append(
                AuditEvent(
                    id: AuditEventID(rawValue: SystemIDGenerator().make()),
                    actor: .cli,
                    action: .tokenIssued,
                    target: "account:\(target.id)",
                    scopes: token.scopes,
                    result: .success,
                    timestamp: runtime.clock.now()))
            Keyloft.streams.writeStdout(token.value)
        } catch RuntimeError.vaultNotInitialized {
            Keyloft.streams.writeStderr("Chưa có vault. Mở Keyloft.app để thêm account.")
            throw ExitCode(KeyloftExitCode.failure.rawValue)
        } catch TokenVaultError.oauth(.invalidGrant) {
            Keyloft.streams.writeStderr(
                "Cần đăng nhập lại: mở Keyloft.app để cấp lại quyền cho account này.")
            throw ExitCode(KeyloftExitCode.needsReauth.rawValue)
        } catch TokenVaultError.oauth(let oauth) where oauth.isTransient {
            Keyloft.streams.writeStderr("Lỗi mạng/provider tạm thời: \(oauth)")
            throw ExitCode(KeyloftExitCode.unreachable.rawValue)
        }
    }
}
