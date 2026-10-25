import Foundation
import KeyloftTestSupport
import SecretVault
import Testing
import VaultDomain

/// Metadata repo có thể hỏng theo yêu cầu (U3).
final class FlakyMetadataRepo: SecretMetadataRepository, @unchecked Sendable {
    /// NSLock + @unchecked Sendable — ngoại lệ Tests/.
    private let lock = NSLock()
    private var failInsert = false
    private let backing = InMemorySecretMetadataRepository()

    func failNextInsert() {
        lock.lock()
        defer { lock.unlock() }
        failInsert = true
    }

    private func shouldFail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return failInsert
    }

    func insert(_ secret: Secret) async throws {
        if shouldFail() {
            throw DomainError.invariantViolated("insert fail theo yêu cầu test")
        }
        try await backing.insert(secret)
    }

    func get(_ id: SecretID) async throws -> Secret? { try await backing.get(id) }
    func list(kind: SecretKind?) async throws -> [Secret] { try await backing.list(kind: kind) }
    func markRotated(_ id: SecretID, at date: Date) async throws {
        try await backing.markRotated(id, at: date)
    }
    func delete(_ id: SecretID) async throws { try await backing.delete(id) }
}

@Suite("SecretVault")
struct SecretVaultTests {
    struct Fixture {
        let db = InMemoryDatabase()
        let store = InMemorySecretStore()
        let audit: InMemoryAuditLog
        let metadata: InMemorySecretMetadataRepository
        let clock = FixedDateProvider()
        let ids = SequentialIDGenerator()
        let vault: SecretVault

        init(metadata custom: (any SecretMetadataRepository)? = nil) {
            let md = InMemorySecretMetadataRepository(db: db)
            self.metadata = md
            self.audit = InMemoryAuditLog(db: db)
            self.vault = SecretVault(
                store: store,
                metadata: custom ?? md,
                audit: audit,
                clock: clock,
                ids: ids)
        }
    }

    @Test("U1: store lỗi khi create → .store, metadata rỗng, không audit")
    func createStoreFails() async throws {
        let f = Fixture()
        await f.store.setFailNextSet(.osStatus(-1))

        await #expect(throws: SecretVaultError.store(.osStatus(-1))) {
            _ = try await f.vault.create(
                kind: .refreshToken, label: "rt", value: Data("x".utf8), actor: .user)
        }
        #expect(try await f.metadata.list(kind: nil).isEmpty)
        let events = try await f.audit.query(AuditQuery())
        #expect(events.filter { $0.action == .secretCreated }.isEmpty)
    }

    @Test("U2: create thành công — item theo ref, metadata, presence mặc định, 1 audit")
    func createHappyPath() async throws {
        let f = Fixture()
        let secret = try await f.vault.create(
            kind: .refreshToken, label: "Google a@b.c", value: Data("rt-value".utf8), actor: .user)

        #expect(secret.requiresUserPresence == false)
        #expect(try await f.store.contains(KeychainRef(kind: .refreshToken, id: secret.id)))
        #expect(try await f.metadata.get(secret.id) != nil)
        let events = try await f.audit.query(AuditQuery(actions: [.secretCreated]))
        #expect(events.count == 1)
        #expect(events.first?.target == "secret:\(secret.id)")
    }

    @Test("U3: metadata lỗi sau khi ghi store → bồi hoàn xóa item, throw .metadata")
    func createMetadataFailsCompensates() async throws {
        let flaky = FlakyMetadataRepo()
        flaky.failNextInsert()
        let f = Fixture(metadata: flaky)

        do {
            _ = try await f.vault.create(
                kind: .clientSecret, label: "cs", value: Data("cs".utf8), actor: .user)
            Issue.record("phải throw .metadata")
        } catch let error as SecretVaultError {
            guard case .metadata = error else {
                Issue.record("kỳ vọng .metadata, được \(error)")
                return
            }
        }
        let stored = await f.store.storedRefs
        #expect(stored.isEmpty, "item Keychain phải được bồi hoàn xóa")
    }

    @Test("U4: presence mặc định theo kind")
    func presenceDefaults() {
        #expect(!SecretVault.defaultRequiresUserPresence(.refreshToken))
        #expect(!SecretVault.defaultRequiresUserPresence(.clientSecret))
        #expect(SecretVault.defaultRequiresUserPresence(.apiKey))
        #expect(SecretVault.defaultRequiresUserPresence(.password))
    }

    @Test("U5: read id không tồn tại → .notFound")
    func readMissing() async throws {
        let f = Fixture()
        let missing = SecretID(rawValue: UUID())
        await #expect(throws: SecretVaultError.notFound(missing)) {
            _ = try await f.vault.read(missing, reason: "test", actor: .user)
        }
    }

    @Test("U6: hủy Touch ID → .store(.userCanceled), không audit secretRead")
    func readUserCanceled() async throws {
        let f = Fixture()
        let secret = try await f.vault.create(
            kind: .apiKey, label: "api", value: Data("k".utf8), actor: .user)
        await f.store.setPresenceGranted(false)

        await #expect(throws: SecretVaultError.store(.userCanceled)) {
            _ = try await f.vault.read(secret.id, reason: "xem api key", actor: .user)
        }
        let events = try await f.audit.query(AuditQuery(actions: [.secretRead]))
        #expect(events.isEmpty)
    }

    @Test("U7: rotate — giá trị mới, rotatedAt = clock, cùng ref, audit secretRotated")
    func rotate() async throws {
        let f = Fixture()
        let secret = try await f.vault.create(
            kind: .refreshToken, label: "rt", value: Data("old".utf8), actor: .user)

        f.clock.advance(by: 120)
        let rotated = try await f.vault.rotate(secret.id, to: Data("new".utf8), actor: .app)

        #expect(rotated.rotatedAt == f.clock.now())
        #expect(rotated.keychainRef == secret.keychainRef)
        let value = try await f.vault.read(secret.id, reason: "test", actor: .app)
        #expect(String(decoding: value, as: UTF8.self) == "new")
        let events = try await f.audit.query(AuditQuery(actions: [.secretRotated]))
        #expect(events.count == 1)
    }

    @Test("U8: không lộ giá trị trong error/audit/Secret")
    func noLeak() async throws {
        let f = Fixture()
        let secretValue = "rt-SECRET-123"
        let secret = try await f.vault.create(
            kind: .refreshToken, label: "rt", value: Data(secretValue.utf8), actor: .user)
        #expect(!String(describing: secret).contains(secretValue))

        // Store lỗi khi create password.
        await f.store.setFailNextSet(.osStatus(-2))
        do {
            _ = try await f.vault.create(
                kind: .password, label: "p", value: Data(secretValue.utf8), actor: .user)
        } catch {
            #expect(!String(describing: error).contains(secretValue))
        }

        // Hủy presence khi đọc apiKey.
        let apiKey = try await f.vault.create(
            kind: .apiKey, label: "a", value: Data(secretValue.utf8), actor: .user)
        await f.store.setPresenceGranted(false)
        do {
            _ = try await f.vault.read(apiKey.id, reason: "r", actor: .cli)
        } catch {
            #expect(!String(describing: error).contains(secretValue))
        }

        for event in try await f.audit.query(AuditQuery()) {
            #expect(!String(describing: event).contains(secretValue))
        }
    }

    @Test("U9: audit theo actor — read .app không ghi, read .cli ghi")
    func auditByActor() async throws {
        let f = Fixture()
        let secret = try await f.vault.create(
            kind: .refreshToken, label: "rt", value: Data("v".utf8), actor: .user)

        _ = try await f.vault.read(secret.id, reason: "refresh", actor: .app)
        _ = try await f.vault.read(secret.id, reason: "cli token", actor: .cli)

        let events = try await f.audit.query(AuditQuery(actions: [.secretRead]))
        #expect(events.count == 1)
        #expect(events.first?.actor == .cli)
    }

    @Test("delete khi item store đã mất → metadata vẫn xóa, không throw")
    func deleteMissingStoreItem() async throws {
        let f = Fixture()
        let secret = try await f.vault.create(
            kind: .password, label: "p", value: Data("v".utf8), actor: .user)
        await f.store.remove(secret.keychainRef)

        try await f.vault.delete(secret.id, actor: .user)
        #expect(try await f.metadata.get(secret.id) == nil)
    }
}
