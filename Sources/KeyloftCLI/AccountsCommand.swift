import ArgumentParser
import Foundation
import VaultDomain
import VaultRuntime

struct AccountsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accounts",
        abstract: "Liệt kê account trong vault")

    @Flag(name: .long, help: "Xuất JSON")
    var json = false

    func run() async throws {
        do {
            let runtime = try Keyloft.makeRuntime()
            let accounts = try await runtime.accounts.list()
            if json {
                let dtos = accounts.map {
                    AccountDTO(
                        id: $0.id.description, provider: $0.providerId.rawValue,
                        email: $0.email, status: $0.status.rawValue)
                }
                let data = try JSONEncoder()
                    .encode(dtos)
                Keyloft.streams.writeStdout(String(decoding: data, as: UTF8.self))
            } else {
                Keyloft.streams.writeStdout(TableFormatter.accountsTable(accounts))
            }
        } catch RuntimeError.vaultNotInitialized {
            Keyloft.streams.writeStderr("Chưa có vault. Mở Keyloft.app để thêm account.")
            throw ExitCode(KeyloftExitCode.failure.rawValue)
        } catch let error as SelectorError {
            Keyloft.streams.writeStderr(Self.describe(error))
            throw ExitCode(KeyloftExitCode.usage.rawValue)
        }
    }

    static func describe(_ error: SelectorError) -> String {
        switch error {
        case .notFound(let query):
            return "Không tìm thấy account: \(query)"
        case .ambiguous(let candidates):
            let list =
                candidates
                .map { "\($0.id.description) (\($0.providerId):\($0.email ?? "-"))" }
                .joined(separator: "\n  ")
            return "Account mơ hồ — các ứng viên:\n  \(list)"
        }
    }
}
