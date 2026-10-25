import Foundation
import KeyloftTestSupport
import Testing
import VaultDomain

@testable import VaultPersistence

@Suite("Core repositories")
struct CoreRepositoryTests {
    struct Rig {
        let db: VaultDatabase
        let clients: GRDBOAuthClientRepository
        let accounts: GRDBAccountRepository
        let credentials: GRDBCredentialRepository
        let secrets: GRDBSecretMetadataRepository

        init() throws {
            db = try VaultDatabase.inMemory()
            clients = GRDBOAuthClientRepository(db: db)
            accounts = GRDBAccountRepository(db: db)
            credentials = GRDBCredentialRepository(db: db)
            secrets = GRDBSecretMetadataRepository(db: db)
        }

        /// Client + secret tương ứng (FK client_secret_ref) + account.
        func seedAccount(externalId: String = "sub-1") async throws -> (OAuthClient, Account) {
            let client = TestData.oauthClient(hasSecret: false)
            try await clients.save(client)
            let account = TestData.account(clientId: client.id, externalId: externalId)
            try await accounts.save(account)
            return (client, account)
        }
    }

    @Test("U4: xóa oauth_client còn account → hasDependents, client còn nguyên")
    func deleteClientWithDependents() async throws {
        let rig = try Rig()
        let (client, _) = try await rig.seedAccount()

        await #expect(throws: DomainError.hasDependents("oauth_client:\(client.id)")) {
            try await rig.clients.delete(client.id)
        }
        #expect(try await rig.clients.get(client.id) != nil)
    }

    @Test("U5: 2 account cùng (provider, client, externalId) → lần 2 .database")
    func accountUnique() async throws {
        let rig = try Rig()
        let (client, _) = try await rig.seedAccount(externalId: "same-sub")
        let duplicate = TestData.account(
            id: AccountID(rawValue: UUID()), clientId: client.id, externalId: "same-sub")
        do {
            try await rig.accounts.save(duplicate)
            Issue.record("phải throw PersistenceError.database")
        } catch let error as PersistenceError {
            guard case .database = error else {
                Issue.record("kỳ vọng .database, được \(error)")
                return
            }
        }
    }

    @Test("U6: find đúng bộ (provider, client, externalId); sai externalId → nil")
    func findAccount() async throws {
        let rig = try Rig()
        let (client, account) = try await rig.seedAccount(externalId: "sub-xyz")

        let found = try await rig.accounts.find(
            provider: account.providerId, oauthClient: client.id, externalId: "sub-xyz")
        #expect(found?.id == account.id)
        let missing = try await rig.accounts.find(
            provider: account.providerId, oauthClient: client.id, externalId: "other")
        #expect(missing == nil)
    }

    @Test("U7: xóa account cascade credential + health; audit giữ nguyên")
    func cascadeDelete() async throws {
        let rig = try Rig()
        let (client, account) = try await rig.seedAccount()

        // Secret cho FK refresh_token_ref + 2 credential.
        let secret = TestData.secret()
        try await rig.secrets.insert(secret)
        let c1 = TestData.credential(
            id: CredentialID(rawValue: UUID()), accountId: account.id,
            refreshTokenRef: secret.id, issuedAt: Date(timeIntervalSince1970: 100))
        let c2 = TestData.credential(
            id: CredentialID(rawValue: UUID()), accountId: account.id,
            refreshTokenRef: secret.id, issuedAt: Date(timeIntervalSince1970: 200))
        try await rig.credentials.insert(c1)
        try await rig.credentials.insert(c2)

        // 3 health result (qua Record — repo là T06) + 1 audit.
        try await rig.db.write { db in
            for i in 0..<3 {
                try HealthCheckRecord(
                    HealthCheckResult(
                        id: HealthCheckID(rawValue: UUID()), accountId: account.id,
                        checkedAt: Date(timeIntervalSince1970: Double(1000 + i)),
                        status: .healthy, checks: [])
                ).insert(db)
            }
            try AuditEventRecord(
                AuditEvent(
                    id: AuditEventID(rawValue: UUID()), actor: .user, action: .accountAdded,
                    target: "account:\(account.id)", result: .success, timestamp: Date())
            ).insert(db)
        }

        try await rig.accounts.delete(account.id)
        #expect(try await rig.credentials.list(for: account.id).isEmpty)
        let healthCount = try await rig.db.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM health_check_result WHERE account_id = ?",
                arguments: [account.id.rawValue.uuidString.lowercased()])
        }
        #expect(healthCount == 0)
        let auditCount = try await rig.db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_event")
        }
        #expect(auditCount == 1)
        // Client không bị cascade (RESTRICT).
        #expect(try await rig.clients.get(client.id) != nil)
    }

    @Test("U8: active lấy issuedAt mới nhất; supersede đúng; id lạ → notFound")
    func credentialActiveAndSupersede() async throws {
        let rig = try Rig()
        let (_, account) = try await rig.seedAccount()
        let secret = TestData.secret()
        try await rig.secrets.insert(secret)

        let c1 = TestData.credential(
            id: CredentialID(rawValue: UUID()), accountId: account.id,
            refreshTokenRef: secret.id, issuedAt: Date(timeIntervalSince1970: 100))
        let c2 = TestData.credential(
            id: CredentialID(rawValue: UUID()), accountId: account.id,
            refreshTokenRef: secret.id, issuedAt: Date(timeIntervalSince1970: 200))
        try await rig.credentials.insert(c1)
        try await rig.credentials.insert(c2)

        #expect(try await rig.credentials.active(for: account.id)?.id == c2.id)

        try await rig.credentials.markSuperseded(c1.id, by: c2.id)
        let superseded = try await rig.credentials.get(c1.id)
        #expect(superseded?.status == .superseded)
        #expect(superseded?.supersededBy == c2.id)
        #expect(try await rig.credentials.active(for: account.id)?.id == c2.id)

        let ghost = CredentialID(rawValue: UUID())
        await #expect(throws: DomainError.notFound("credential:\(ghost)")) {
            try await rig.credentials.markSuperseded(ghost, by: c2.id)
        }
    }

    @Test("Edge: list rỗng trả []; updateStatus id lạ → notFound")
    func emptyListAndMissingStatus() async throws {
        let rig = try Rig()
        #expect(try await rig.clients.list(provider: nil).isEmpty)
        #expect(try await rig.accounts.list().isEmpty)
        #expect(try await rig.secrets.list(kind: nil).isEmpty)

        let ghost = AccountID(rawValue: UUID())
        await #expect(throws: DomainError.notFound("account:\(ghost)")) {
            try await rig.accounts.updateStatus(ghost, to: .degraded, at: Date())
        }
    }

    @Test("Edge: secret bị credential tham chiếu → hasDependents; revoke + updateScopes")
    func secretDependentsAndUpdates() async throws {
        let rig = try Rig()
        let (_, account) = try await rig.seedAccount()
        let secret = TestData.secret()
        try await rig.secrets.insert(secret)
        let credential = TestData.credential(accountId: account.id, refreshTokenRef: secret.id)
        try await rig.credentials.insert(credential)

        await #expect(throws: DomainError.hasDependents("secret:\(secret.id)")) {
            try await rig.secrets.delete(secret.id)
        }

        try await rig.credentials.markRevoked(credential.id)
        #expect(try await rig.credentials.get(credential.id)?.status == .revoked)

        try await rig.credentials.updateGrantedScopes(credential.id, ["openid"])
        #expect(try await rig.credentials.get(credential.id)?.grantedScopes == ["openid"])
    }
}
