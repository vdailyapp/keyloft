import Foundation
import Testing
import TokenVault
import VaultDomain
import VaultRuntime
import KeyloftTestSupport
@testable import Keyloft

@MainActor
@Suite("OAuth clients")
struct OAuthClientsTests {
    @Test("U9: form validate — client ID rỗng; Dropbox redirect thiếu port; Microsoft thiếu ngày hết hạn")
    func formValidation() {
        var values = OAuthClientFormValues(label: "Google app", clientID: "cid-123")
        #expect(validateOAuthClientForm(values, provider: .google) == nil)

        // Client ID rỗng (kể cả toàn khoảng trắng).
        values.clientID = "   "
        #expect(validateOAuthClientForm(values, provider: .google) == .missingClientID)
        values.clientID = "cid-123"

        // Redirect không phải loopback /callback → invalid.
        values.redirectURI = "http://127.0.0.1:53682/other"
        #expect(validateOAuthClientForm(values, provider: .google) == .invalidRedirectURI)

        // Dropbox: loopback nhưng không port → bắt buộc cổng cố định.
        values.redirectURI = "http://127.0.0.1/callback"
        #expect(validateOAuthClientForm(values, provider: .dropbox) == .dropboxRedirectNeedsPort)
        values.redirectURI = "http://127.0.0.1:53682/callback"
        #expect(validateOAuthClientForm(values, provider: .dropbox) == nil)

        // Microsoft: bắt buộc ngày hết hạn secret.
        #expect(validateOAuthClientForm(values, provider: .microsoft) == .microsoftNeedsSecretExpiry)
        values.secretExpiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(validateOAuthClientForm(values, provider: .microsoft) == nil)
    }

    @Test("U10: lưu client có secret — Secret kind clientSecret tạo, ref set, giá trị không nằm trong model")
    func saveWithSecret() async throws {
        let runtime = try await AccountsTests.makeRuntime()
        let model = OAuthClientsModel(runtime: runtime)

        await model.save(
            provider: .google,
            values: OAuthClientFormValues(
                label: "My Google", clientID: "cid-app",
                clientSecret: "GOCSPX-super-secret-value"))

        #expect(model.error == nil)
        let clients = try await runtime.clients.list(provider: .google)
        #expect(clients.count == 1)
        let ref = try #require(clients[0].clientSecretRef)

        let secrets = try await runtime.secrets.list(kind: .clientSecret)
        #expect(secrets.map(\.id).contains(ref))
        let value = try await runtime.secrets.read(ref, reason: "test", actor: .user)
        #expect(String(decoding: value, as: UTF8.self) == "GOCSPX-super-secret-value")

        // Giá trị secret không nằm trong thuộc tính nào của model sau khi lưu.
        let dump = Mirror(reflecting: model).children
            .compactMap { "\($0.value)" }.joined(separator: "|")
        #expect(!dump.contains("GOCSPX-super-secret-value"))
    }

    @Test("U11: xóa client còn account → thông báo 'Còn N account dùng client này', không xóa")
    func deleteBlockedByAccounts() async throws {
        let runtime = try await AccountsTests.makeRuntime()
        let model = OAuthClientsModel(runtime: runtime)
        await model.save(
            provider: .google,
            values: OAuthClientFormValues(label: "g", clientID: "cid-shared"))
        let client = try #require(try await runtime.clients.list(provider: .google).first)
        try await runtime.accounts.save(
            TestData.account(clientId: client.id, externalId: "a"))
        try await runtime.accounts.save(
            TestData.account(
                id: AccountID(rawValue: UUID()), clientId: client.id, externalId: "b"))

        await model.delete(client.id)

        #expect(model.deletionBlockedMessage == "Còn 2 account dùng client này")
        #expect(try await runtime.clients.get(client.id) != nil)
    }

    @Test("U11 (phụ): xóa client không còn account → xóa được, không thông báo")
    func deleteWithoutAccounts() async throws {
        let runtime = try await AccountsTests.makeRuntime()
        let model = OAuthClientsModel(runtime: runtime)
        await model.save(
            provider: .dropbox,
            values: OAuthClientFormValues(
                label: "dbx", clientID: "cid-dbx",
                redirectURI: "http://127.0.0.1:53682/callback"))
        let client = try #require(try await runtime.clients.list(provider: .dropbox).first)

        await model.delete(client.id)

        #expect(model.deletionBlockedMessage == nil)
        #expect(try await runtime.clients.get(client.id) == nil)
    }
}
