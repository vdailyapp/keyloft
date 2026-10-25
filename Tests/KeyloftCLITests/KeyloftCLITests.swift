import ArgumentParser
import Foundation
import KeyloftTestSupport
import Testing
import TokenVault
import VaultDomain
import VaultRuntime

@testable import KeyloftCLI

/// Ghi stdout/stderr vào buffer để assert.
final class BufferStreams: StandardStreams, @unchecked Sendable {
    // NSLock + @unchecked Sendable — ngoại lệ Tests/.
    private let lock = NSLock()
    private var out: [String] = []
    private var err: [String] = []

    func writeStdout(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        out.append(text)
    }

    func writeStderr(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        err.append(text)
    }

    var stdout: String {
        lock.lock()
        defer { lock.unlock() }
        return out.joined(separator: "\n")
    }
    var stderr: String {
        lock.lock()
        defer { lock.unlock() }
        return err.joined(separator: "\n")
    }
}

@Suite("Keyloft CLI", .serialized)
struct KeyloftCLITests {
    struct Fixture {
        let runtime: VaultRuntime
        let stub: StubHTTPClient
        let store: InMemorySecretStore
        let streams: BufferStreams
        let client: OAuthClient
        let account: Account

        static func make(
            accountStatus: AccountStatus = .healthy,
            email: String = "me@example.test",
            secondAccount: Bool = false,
            tokenFails: Bool = false
        ) async throws -> Fixture {
            let stub = StubHTTPClient()
            let clock = FixedDateProvider()
            let store = InMemorySecretStore()

            let runtime = VaultRuntime(
                RuntimeDependencies.inMemory(
                    http: stub,
                    browser: FakeBrowserSession(behavior: .cancel),
                    clock: clock,
                    ids: SequentialIDGenerator(),
                    random: SeededRandomSource(seed: 5),
                    store: store))

            let client = TestData.oauthClient(
                provider: .google, clientId: "cli-client", hasSecret: false)
            try await runtime.clients.save(client)
            let account = TestData.account(
                id: AccountID(rawValue: UUID()), clientId: client.id,
                externalId: "sub-cli", email: email, status: accountStatus)
            try await runtime.accounts.save(account)

            if tokenFails {
                stub.on(
                    "POST", "https://oauth2.googleapis.com/token", status: 400,
                    json: #"{"error":"invalid_grant"}"#)
            } else {
                stub.on(
                    "POST", "https://oauth2.googleapis.com/token",
                    json: #"{"access_token":"cli-at","token_type":"Bearer","expires_in":3600}"#)
            }
            stub.on(
                "GET", "https://www.googleapis.com",
                json: #"{"user": {"emailAddress": "me@example.test"}, "storageQuota": {"usage": "1", "limit": "100"}}"#)

            // Credential + secret để accessToken chạy được.
            try await runtime.secrets.create(
                kind: .refreshToken, label: "rt", value: Data("rt-cli".utf8), actor: .user)
            let created = try await runtime.secrets.list(kind: .refreshToken).first!
            try await runtime.credentials.insert(
                TestData.credential(accountId: account.id, refreshTokenRef: created.id))

            if secondAccount {
                let other = TestData.account(
                    provider: .microsoft,
                    id: AccountID(rawValue: UUID()),
                    clientId: client.id, externalId: "sub-cli-2", email: email,
                    status: .healthy)
                try await runtime.accounts.save(other)
            }

            let streams = BufferStreams()
            Keyloft.streams = streams
            return Fixture(
                runtime: runtime, stub: stub, store: store, streams: streams,
                client: client, account: account)
        }
    }

    private func resetFactory() {
        Keyloft.makeRuntime = { throw RuntimeError.vaultNotInitialized }
    }

    /// parse rồi run, giữ lỗi ExitCode nguyên vẹn cho caller bắt.
    static func runCommand(_ command: some AsyncParsableCommand) async throws {
        var mutable = command
        try await mutable.run()
    }

    // MARK: - Selector & exit code thuần

    @Test("U1: selector UUID đầy đủ / tiền tố 4 / tiền tố 3")
    func selectorUUID() throws {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let account = TestData.account(id: AccountID(rawValue: id))
        let accounts = [account]

        guard
            case .success(let full) = AccountSelector.resolve(
                "12345678-1234-1234-1234-123456789ABC", in: accounts)
        else {
            Issue.record("UUID đầy đủ phải khớp")
            return
        }
        #expect(full.id == account.id)

        guard case .success(let prefix) = AccountSelector.resolve("12345678", in: accounts) else {
            Issue.record("tiền tố 8 ký tự phải khớp")
            return
        }
        #expect(prefix.id == account.id)

        guard case .success(let short) = AccountSelector.resolve("1234", in: accounts) else {
            Issue.record("tiền tố 4 ký tự phải khớp")
            return
        }
        #expect(short.id == account.id)

        guard case .failure(.notFound) = AccountSelector.resolve("123", in: accounts) else {
            Issue.record("tiền tố < 4 không hợp lệ")
            return
        }
    }

    @Test("U2: selector email không phân biệt hoa thường")
    func selectorEmailCase() throws {
        let account = TestData.account(email: "Me@Example.Test")
        guard
            case .success(let match) = AccountSelector.resolve(
                "me@example.test", in: [account])
        else {
            Issue.record("email hoa thường phải khớp")
            return
        }
        #expect(match.id == account.id)
    }

    @Test("U3: selector mơ hồ → ambiguous; provider:email → ok")
    func selectorAmbiguous() throws {
        let google = TestData.account(provider: .google, email: "a@x.com")
        let microsoft = TestData.account(
            provider: .microsoft,
            id: AccountID(rawValue: UUID()),
            externalId: "sub-ms", email: "a@x.com")
        let accounts = [google, microsoft]

        guard
            case .failure(.ambiguous(let candidates)) = AccountSelector.resolve(
                "a@x.com", in: accounts)
        else {
            Issue.record("email trùng 2 provider phải ambiguous")
            return
        }
        #expect(candidates.count == 2)

        guard
            case .success(let match) = AccountSelector.resolve(
                "google:a@x.com", in: accounts)
        else {
            Issue.record("provider:email phải khớp")
            return
        }
        #expect(match.id == google.id)
    }

    @Test("U4: exit code từng status")
    func exitCodes() {
        #expect(KeyloftExitCode.from(.healthy) == .ok)
        #expect(KeyloftExitCode.from(.degraded) == .ok)
        #expect(KeyloftExitCode.from(.needsReauth) == .needsReauth)
        #expect(KeyloftExitCode.from(.needsConsent) == .needsConsent)
        #expect(KeyloftExitCode.from(.unreachable) == .unreachable)
    }

    @Test("U5: worst theo severity")
    func worstCode() {
        #expect(
            KeyloftExitCode.worst([.healthy, .unreachable, .needsConsent]) == .needsConsent)
        #expect(
            KeyloftExitCode.worst([.healthy, .unreachable]) == .unreachable)
        #expect(KeyloftExitCode.worst([]) == .ok)
    }

    // MARK: - Lệnh

    @Test("U6: token — stdout chỉ token, stderr rỗng, exit 0")
    func tokenStdout() async throws {
        let fixture = try await Fixture.make()
        Keyloft.makeRuntime = { fixture.runtime }

        try await Self.runCommand(await TokenCommand.asyncParse(["me@example.test"]))
        #expect(fixture.streams.stdout == "cli-at")
        #expect(fixture.streams.stderr.isEmpty)
    }

    @Test("U7: token — audit token.issued actor cli")
    func tokenAudit() async throws {
        let fixture = try await Fixture.make()
        Keyloft.makeRuntime = { fixture.runtime }

        _ = try? await Self.runCommand(await TokenCommand.asyncParse(["me@example.test"]))
        let events = try await fixture.runtime.audit.query(
            AuditQuery(actions: [.tokenIssued]))
        #expect(events.count == 1)
        #expect(events.first?.actor == .cli)
        #expect(events.first?.target == "account:\(fixture.account.id)")
    }

    @Test("U8: token needsReauth — stdout rỗng, stderr gợi ý app, exit 2")
    func tokenNeedsReauth() async throws {
        let fixture = try await Fixture.make(tokenFails: true)
        Keyloft.makeRuntime = { fixture.runtime }

        do {
            try await Self.runCommand(await TokenCommand.asyncParse(["me@example.test"]))
            Issue.record("phải throw ExitCode(2)")
        } catch let exit as ExitCode {
            #expect(exit.rawValue == 2)
        }
        #expect(fixture.streams.stdout.isEmpty)
        #expect(fixture.streams.stderr.contains("Keyloft.app"))
    }

    @Test("U9: token --force — đúng 1 request refresh dù cache còn hạn")
    func tokenForce() async throws {
        let fixture = try await Fixture.make()
        Keyloft.makeRuntime = { fixture.runtime }

        _ = try? await Self.runCommand(await TokenCommand.asyncParse(["me@example.test"]))
        let refreshCalls = fixture.stub.requests.count { $0.url!.host == "oauth2.googleapis.com" }
        #expect(refreshCalls == 1)

        _ = try? await Self.runCommand(await TokenCommand.asyncParse(["me@example.test", "--force"]))
        let total = fixture.stub.requests.count { $0.url!.host == "oauth2.googleapis.com" }
        #expect(total == 2)
    }

    @Test("U10: health --json — 2 account, decode DTO, exit theo worst")
    func healthJSON() async throws {
        let fixture = try await Fixture.make(secondAccount: true)
        Keyloft.makeRuntime = { fixture.runtime }

        struct DTO: Decodable {
            struct Check: Decodable {
                let name: String
                let ok: Bool
            }
            struct AccountPart: Decodable {
                let id: String
                let provider: String
                let email: String?
            }
            let account: AccountPart
            let status: String
            let checkedAt: String
            let checks: [Check]
        }

        do {
            try await Self.runCommand(await HealthCommand.asyncParse(["--json"]))
            Issue.record("phải throw ExitCode của trạng thái nặng nhất")
        } catch let exit as ExitCode {
            // Account microsoft không có credential → needsReauth (2) là nặng nhất.
            #expect(exit.rawValue == 2)
        }
        let stdout = fixture.streams.stdout
        let dtos = try JSONDecoder().decode([DTO].self, from: Data(stdout.utf8))
        #expect(dtos.count == 2)
        #expect(dtos.allSatisfy { !$0.checkedAt.isEmpty })
    }

    @Test("U11: accounts — header + 3 dòng, ID 8 ký tự")
    func accountsTable() async throws {
        let fixture = try await Fixture.make()
        for i in 1...2 {
            try await fixture.runtime.accounts.save(
                TestData.account(
                    id: AccountID(rawValue: UUID()), clientId: fixture.client.id,
                    externalId: "sub-\(i)", email: "u\(i)@example.test"))
        }
        Keyloft.makeRuntime = { fixture.runtime }

        _ = try? await Self.runCommand(await AccountsCommand.asyncParse([]))
        let lines = fixture.streams.stdout.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        #expect(lines[0].contains("PROVIDER"))
        for line in lines.dropFirst() {
            #expect(line.split(separator: " ").first?.count == 8)
        }
    }

    @Test("U12: chưa có vault — thông điệp + exit 1")
    func vaultNotInitialized() async throws {
        let fixture = try await Fixture.make()
        resetFactory()

        do {
            try await Self.runCommand(await AccountsCommand.asyncParse([]))
            Issue.record("phải throw ExitCode(1)")
        } catch let exit as ExitCode {
            #expect(exit.rawValue == 1)
        }
        #expect(fixture.streams.stderr.contains("Chưa có vault"))
        _ = fixture
    }
}
