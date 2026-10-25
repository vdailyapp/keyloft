import Foundation
import Testing

@testable import VaultDomain

@Suite("Entity Codable round-trip")
struct EntityCodableTests {
    static let day = Date(timeIntervalSince1970: 1_761_353_600)

    @Test("U7: round-trip Account, Credential, OAuthClient, Secret, HealthCheckResult, AuditEvent")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let account = Account(
            id: AccountID(rawValue: UUID()), providerId: .google,
            oauthClientId: OAuthClientID(rawValue: UUID()), externalId: "sub-123",
            email: "a@b.c", displayName: "A B", status: .healthy,
            statusChangedAt: Self.day, createdAt: Self.day)
        let credential = Credential(
            id: CredentialID(rawValue: UUID()), accountId: account.id,
            refreshTokenRef: SecretID(rawValue: UUID()),
            requestedScopes: ["openid", "email"], grantedScopes: ["openid"],
            issuedAt: Self.day, status: .active)
        let client = OAuthClient(
            id: OAuthClientID(rawValue: UUID()), providerId: .google, clientId: "cid",
            clientSecretRef: SecretID(rawValue: UUID()),
            redirectURI: URL(string: "http://127.0.0.1/callback")!, label: "Main",
            createdAt: Self.day)
        let secret = Secret(
            id: SecretID(rawValue: UUID()), kind: .refreshToken, label: "rt",
            keychainRef: KeychainRef(kind: .refreshToken, id: SecretID(rawValue: UUID())),
            requiresUserPresence: false, createdAt: Self.day)
        let health = HealthCheckResult(
            id: HealthCheckID(rawValue: UUID()), accountId: account.id, checkedAt: Self.day,
            status: .degraded,
            checks: [HealthCheckItem(name: .tokenPresent, ok: true, warnings: [])])
        let audit = AuditEvent(
            id: AuditEventID(rawValue: UUID()), actor: .user, action: .scopeGranted,
            target: "account:\(account.id)", scopes: ["openid"],
            result: .failure(reason: "test"), timestamp: Self.day)

        #expect(try decoder.decode(Account.self, from: encoder.encode(account)) == account)
        #expect(try decoder.decode(Credential.self, from: encoder.encode(credential)) == credential)
        #expect(try decoder.decode(OAuthClient.self, from: encoder.encode(client)) == client)
        #expect(try decoder.decode(Secret.self, from: encoder.encode(secret)) == secret)
        #expect(try decoder.decode(HealthCheckResult.self, from: encoder.encode(health)) == health)
        #expect(try decoder.decode(AuditEvent.self, from: encoder.encode(audit)) == audit)
    }

    @Test("U7: ID encode thành chuỗi UUID thường, không phải object")
    func idEncodesAsString() throws {
        let uuid = UUID(uuidString: "6F1C0D6A-8B44-4E4A-9C1D-2B6A0F99B211")!
        let data = try JSONEncoder().encode(AccountID(rawValue: uuid))
        #expect(String(decoding: data, as: UTF8.self) == "\"6f1c0d6a-8b44-4e4a-9c1d-2b6a0f99b211\"")
    }
}
