import ArgumentParser
import VaultRuntime

@main
struct Keyloft: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keyloft",
        abstract: "Token/secret vault cho macOS",
        version: "0.1.0",
        subcommands: [AccountsCommand.self, HealthCommand.self, TokenCommand.self]
    )

    // Ngoại lệ AGENTS.md (nonisolated(unsafe)): SPEC-010 §2 đòi mutable factory để test
    // bơm runtime in-memory; chỉ gán một lần lúc test setup, không chia sẻ state khác.
    nonisolated(unsafe) static var makeRuntime: @Sendable () throws -> VaultRuntime = {
        try VaultRuntime.live(context: .cli, browser: UnavailableBrowserSession())
    }

    // Test thay bằng buffer streams; chỉ gán lúc setup.
    nonisolated(unsafe) static var streams: any StandardStreams = ProcessStreams()

    func run() async throws {
        Keyloft.streams.writeStdout("keyloft \(Self.configuration.version)")
    }
}
