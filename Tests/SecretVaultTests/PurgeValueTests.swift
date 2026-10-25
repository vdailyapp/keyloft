import Foundation
import KeyloftTestSupport
import SecretVault
import Testing
import VaultDomain

@Suite("SecretVault.purgeValue")
struct PurgeValueTests {
    @Test("U14: item Keychain mất; metadata còn, rotatedAt set; audit secret.deleted")
    func purge() async throws {
        let db = InMemoryDatabase()
        let store = InMemorySecretStore()
        let audit = InMemoryAuditLog(db: db)
        let clock = FixedDateProvider()
        let vault = SecretVault(
            store: store,
            metadata: InMemorySecretMetadataRepository(db: db),
            audit: audit,
            clock: clock,
            ids: SequentialIDGenerator())

        let secret = try await vault.create(
            kind: .refreshToken, label: "rt", value: Data("rt-value".utf8), actor: .user)
        clock.advance(by: 99)

        try await vault.purgeValue(secret.id, actor: .app)

        #expect(try await store.contains(secret.keychainRef) == false)
        let metadata = try await vault.get(secret.id)
        #expect(metadata != nil)
        #expect(metadata?.rotatedAt == clock.now())
        let events = try await audit.query(AuditQuery(actions: [.secretDeleted]))
        #expect(events.count == 1)
        #expect(events.first?.target == "secret:\(secret.id)")
    }

    @Test("U14: purge id lạ → notFound")
    func purgeMissing() async throws {
        let db = InMemoryDatabase()
        let vault = SecretVault(
            store: InMemorySecretStore(),
            metadata: InMemorySecretMetadataRepository(db: db),
            audit: InMemoryAuditLog(db: db),
            clock: FixedDateProvider(),
            ids: SequentialIDGenerator())
        let missing = SecretID(rawValue: UUID())
        await #expect(throws: SecretVaultError.notFound(missing)) {
            try await vault.purgeValue(missing, actor: .app)
        }
    }
}

extension SecretVault {
    /// Helper test: đọc metadata 1 secret.
    public func get(_ id: SecretID) async throws -> Secret? {
        try await list(kind: nil).first { $0.id == id }
    }
}
