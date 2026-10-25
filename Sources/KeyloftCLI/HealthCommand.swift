import ArgumentParser
import Foundation
import VaultDomain
import VaultRuntime

struct HealthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "health",
        abstract: "Kiểm tra sức khỏe account")

    @Flag(name: .long, help: "Xuất JSON")
    var json = false

    @Argument(help: "Account (UUID, tiền tố ≥ 4, email, hoặc provider:email)")
    var account: String?

    func run() async throws {
        do {
            let runtime = try Keyloft.makeRuntime()
            let accounts = try await runtime.accounts.list()

            var targets = accounts
            if let query = account {
                switch AccountSelector.resolve(query, in: accounts) {
                case .success(let match):
                    targets = [match]
                case .failure(let error):
                    Keyloft.streams.writeStderr(AccountsCommand.describe(error))
                    throw ExitCode(KeyloftExitCode.usage.rawValue)
                }
            }

            // Check trực tiếp, tối đa 3 song song — CLI không start scheduler.
            let results = try await withThrowingTaskGroup(
                of: (Account, HealthCheckResult).self
            ) { group in
                var iterator = targets.makeIterator()
                var collected: [(Account, HealthCheckResult)] = []
                func addNext() -> Bool {
                    guard let account = iterator.next() else { return false }
                    let checker = runtime.health
                    group.addTask { (account, try await checker.check(account.id, actor: .cli)) }
                    return true
                }
                for _ in 0..<3 where addNext() {}
                while let pair = try await group.next() {
                    collected.append(pair)
                    _ = addNext()
                }
                return collected.sorted { $0.0.createdAt < $1.0.createdAt }
            }

            if json {
                let dtos = results.map { HealthDTO(account: $0.0, result: $0.1) }
                let data = try JSONEncoder()
                    .encode(dtos)
                Keyloft.streams.writeStdout(String(decoding: data, as: UTF8.self))
            } else {
                Keyloft.streams.writeStdout(TableFormatter.healthTable(results.map(\.1)))
            }
            throw ExitCode(KeyloftExitCode.worst(results.map { $0.1.status }).rawValue)
        } catch RuntimeError.vaultNotInitialized {
            Keyloft.streams.writeStderr("Chưa có vault. Mở Keyloft.app để thêm account.")
            throw ExitCode(KeyloftExitCode.failure.rawValue)
        } catch let error as SelectorError {
            Keyloft.streams.writeStderr(AccountsCommand.describe(error))
            throw ExitCode(KeyloftExitCode.usage.rawValue)
        }
    }
}
