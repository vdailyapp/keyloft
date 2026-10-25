import ArgumentParser
import VaultRuntime

@main
struct Keyloft: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keyloft",
        abstract: "Token/secret vault cho macOS",
        version: "0.1.0"
    )

    func run() async throws {
        // Placeholder T01; subcommand thật thêm ở T24 (SPEC-010).
        print("keyloft \(Self.configuration.version)")
    }
}
