import Foundation
import Testing
import TokenVault
import VaultDomain
import VaultRuntime
import KeyloftTestSupport
@testable import Keyloft

@MainActor
@Suite("Accounts model")
struct AccountsTests {
    /// Runtime fake đầy đủ cho model app (TESTING SPEC-011 môi trường).
    static func makeRuntime(
        browserBehavior: FakeBrowserSession.Behavior = .redirect(
            code: "app-code", state: .echo, iss: nil)
    ) async throws -> VaultRuntime {
        let stub = StubHTTPClient()
        let provider = TestData.googleProvider
        let idToken = TestJWT.make(
            claims: TestJWT.claims(
                iss: provider.issuer, sub: "sub-app", aud: ["app-client"]))
        stub.on(
            "POST", "https://oauth2.googleapis.com/token",
            json: #"{"access_token":"app-at","token_type":"Bearer","refresh_token":"app-rt","expires_in":3600,"scope":"openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/drive","id_token":""# + idToken + #""}"#)
        stub.on(
            "GET", "https://www.googleapis.com",
            json: #"{"user": {"emailAddress": "app@example.test"}, "storageQuota": {"usage": "1", "limit": "100"}}"#)
        return VaultRuntime(
            RuntimeDependencies.inMemory(
                http: stub,
                browser: FakeBrowserSession(behavior: browserBehavior),
                clock: FixedDateProvider(),
                ids: SequentialIDGenerator(),
                random: SeededRandomSource(seed: 31),
                store: InMemorySecretStore()))
    }

    static func seedClient(_ runtime: VaultRuntime) async throws -> OAuthClient {
        let client = TestData.oauthClient(
            provider: .google, clientId: "app-client", hasSecret: false)
        try await runtime.clients.save(client)
        return client
    }

    @Test("U3: load 2 account đúng trạng thái")
    func loadRows() async throws {
        let runtime = try await Self.makeRuntime()
        let client = try await Self.seedClient(runtime)
        try await runtime.accounts.save(
            TestData.account(clientId: client.id, externalId: "a", status: .healthy))
        try await runtime.accounts.save(
            TestData.account(
                id: AccountID(rawValue: UUID()), clientId: client.id, externalId: "b",
                status: .needsReauth))

        let model = AccountsModel(runtime: runtime)
        await model.load()
        #expect(model.rows.count == 2)
        #expect(model.rows.map(\.status).contains(.needsReauth))
        #expect(model.rows.map(\.status).contains(.healthy))
    }

    @Test("U4: thêm account thành công — row mới, không error")
    func addSuccess() async throws {
        let runtime = try await Self.makeRuntime()
        let client = try await Self.seedClient(runtime)

        let model = AccountsModel(runtime: runtime)
        await model.load()
        await model.add(provider: .google, client: client.id)

        #expect(model.error == nil)
        #expect(model.rows.count == 1)
        // Repo là nguồn sự thật: account healthy + credential active sau login.
        let accounts = try await runtime.accounts.list()
        #expect(accounts.count == 1)
        #expect(accounts.first?.status == .healthy)
        let active = try await runtime.credentials.active(for: accounts[0].id)
        #expect(active != nil)
    }

    @Test("U5: thêm account hủy — error 'Đã hủy đăng nhập', rows không đổi")
    func addCancelled() async throws {
        let runtime = try await Self.makeRuntime(browserBehavior: .cancel)
        let client = try await Self.seedClient(runtime)

        let model = AccountsModel(runtime: runtime)
        await model.load()
        await model.add(provider: .google, client: client.id)

        // Lỗi hủy map thành câu thân thiện cho người dùng, không chuỗi debug.
        #expect(model.error == "Đã hủy đăng nhập")
        #expect(model.rows.isEmpty)
        #expect(try await runtime.accounts.list().isEmpty)
    }

    @Test("U6: cập nhật từ scheduler.updates đổi status không cần load")
    func updatesFlow() async throws {
        let runtime = try await Self.makeRuntime()
        let client = try await Self.seedClient(runtime)
        let account = TestData.account(clientId: client.id)
        try await runtime.accounts.save(account)

        let model = AccountsModel(runtime: runtime)
        await model.load()
        model.observeUpdates()

        // Đẩy kết quả như scheduler.updates sẽ phát.
        await MainActor.run {
            model.apply(
                HealthCheckResult(
                    id: HealthCheckID(rawValue: UUID()), accountId: account.id,
                    checkedAt: Date(), status: .needsConsent, checks: []))
        }
        #expect(model.rows.first?.status == .needsConsent)
        model.stopObserving()
    }

    @Test("U7: remove Google thiếu ack → pendingConfirmation, không gọi revoke")
    func removeNeedsAck() async throws {
        let runtime = try await Self.makeRuntime()
        let client = try await Self.seedClient(runtime)
        let account = TestData.account(clientId: client.id)
        try await runtime.accounts.save(account)

        let model = AccountsModel(runtime: runtime)
        await model.load()
        await model.remove(account.id, ack: false)

        #expect(model.pendingConfirmation == .grantWideRevocation(account.id))
        // Account vẫn còn (chưa xóa vì chưa ack).
        #expect(try await runtime.accounts.get(account.id) != nil)
    }

    @Test("U17: relogin lỗi → model.error hiện cho người dùng, không im lặng")
    func reloginErrorSurfaces() async throws {
        let runtime = try await Self.makeRuntime(browserBehavior: .cancel)
        let client = try await Self.seedClient(runtime)
        let account = TestData.account(clientId: client.id)
        try await runtime.accounts.save(account)

        let model = AccountsModel(runtime: runtime)
        await model.load()
        await model.perform(.reauth, on: account.id)

        #expect(model.error == "Đã hủy đăng nhập")
    }
}


