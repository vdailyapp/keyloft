import Foundation
import GRDB
import KeyloftTestSupport
import Testing
import VaultDomain

@testable import VaultPersistence

/// FileManager giả luôn lỗi khi setAttributes — test chmod phải throw (T30).
private final class ThrowingAttributesFM: FileManager {
    override func setAttributes(
        _ attributes: [FileAttributeKey: Any], ofItemAtPath path: String
    ) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

@Suite("VaultDatabase")
struct DatabaseTests {
    static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("keyloft-test-\(UUID().uuidString).sqlite")
    }

    @Test("U1: mở file mới — thư mục 0700, file 0600, WAL, v1_initial đã áp dụng")
    func openFilePermissions() async throws {
        let url = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: url) }

        let db = try VaultDatabase.open(at: url)

        let dirAttrs = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        #expect((dirAttrs[.posixPermissions] as? Int)! & 0o777 == 0o700)
        let fileAttrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((fileAttrs[.posixPermissions] as? Int)! & 0o777 == 0o600)

        let mode = try await db.writer.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        #expect(mode == "wal")

        let applied = try await db.writer.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        }
        #expect(applied == ["v1_initial"])
    }

    @Test("U2: DB có migration lạ (mới hơn app) → schemaTooNew")
    func schemaTooNew() async throws {
        let url = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try VaultDatabase.open(at: url)
        try await first.writer.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99_future')")
        }
        #expect(throws: PersistenceError.schemaTooNew) {
            _ = try VaultDatabase.open(at: url)
        }
    }

    @Test("U3: ngày lưu dạng số (real), thứ tự theo thời gian")
    func datesStoredAsReal() async throws {
        let db = try VaultDatabase.inMemory()
        let client = TestData.oauthClient(hasSecret: false)
        try await db.writer.write { db in
            try OAuthClientRecord(client).insert(db)
        }

        let older = TestData.account(
            id: AccountID(rawValue: UUID()), externalId: "sub-older",
            createdAt: Date(timeIntervalSince1970: 100))
        let newer = TestData.account(
            id: AccountID(rawValue: UUID()), externalId: "sub-newer",
            createdAt: Date(timeIntervalSince1970: 9_000))
        try await db.writer.write { db in
            try AccountRecord(older).insert(db)
            try AccountRecord(newer).insert(db)
        }

        let rows = try await db.writer.read { db in
            try AccountRecord
                .order(Column("created_at")).fetchAll(db)
        }
        #expect(
            rows.map(\.id) == [older.id.rawValue.uuidString.lowercased(), newer.id.rawValue.uuidString.lowercased()])

        let type = try await db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT typeof(created_at) FROM account LIMIT 1")
        }
        #expect(type == "real")
    }

    @Test("U9: audit_event append-only — UPDATE/DELETE bị trigger chặn")
    func auditAppendOnly() async throws {
        let db = try VaultDatabase.inMemory()
        try await db.writer.write { db in
            try AuditEventRecord(
                AuditEvent(
                    id: AuditEventID(rawValue: UUID()), actor: .user, action: .tokenRefreshed,
                    target: "account:x", result: .success, timestamp: Date())
            ).insert(db)
        }

        await #expect(throws: Error.self) {
            try await db.writer.write { db in
                try db.execute(sql: "UPDATE audit_event SET target = 'tampered'")
            }
        }
        do {
            try await db.writer.write { db in
                try db.execute(sql: "DELETE FROM audit_event")
            }
            Issue.record("DELETE phải bị chặn")
        } catch let error as DatabaseError {
            #expect(String(describing: error).contains("append-only"))
        }
    }

    @Test("U13: hàng hỏng (status lạ) → corruptRow khi decode")
    func corruptRow() async throws {
        let db = try VaultDatabase.inMemory()
        let account = TestData.account()
        try await db.writer.write { db in
            try OAuthClientRecord(TestData.oauthClient(hasSecret: false)).insert(db)
            try AccountRecord(account).insert(db)
            try db.execute(
                sql: "UPDATE account SET status = 'bogus' WHERE id = ?",
                arguments: [account.id.rawValue.uuidString.lowercased()])
        }

        let row = try await db.writer.read { db in
            try AccountRecord.fetchOne(
                db, key: account.id.rawValue.uuidString.lowercased())
        }
        #expect(row != nil)
        await #expect(
            throws: PersistenceError.corruptRow(
                table: "account", id: account.id.rawValue.uuidString.lowercased())
        ) {
            _ = try row!.toEntity()
        }
    }

    @Test("I1: hai DatabasePool cùng file, ghi xen kẽ 200 lần không locked")
    func twoWriters() async throws {
        let url = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = try VaultDatabase.open(at: url)
        let b = try VaultDatabase.open(at: url)

        async let left: Void = writeBatch(a, tag: "a")
        async let right: Void = writeBatch(b, tag: "b")
        _ = try await (left, right)

        let count = try await a.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_event")
        }
        #expect(count == 200)
    }

    @Test("U14: thư mục chỉ đọc → open throw (không mở DB với quyền rộng)")
    func readOnlyDirectory() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyloft-ro-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer {
            // Chỉ đọc → khôi phục quyền trước khi xóa rác test.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: base.path)
            try? FileManager.default.removeItem(at: base)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: base.path)

        #expect(throws: (any Error).self) {
            _ = try VaultDatabase.open(at: base.appendingPathComponent("vault.sqlite"))
        }
    }

    @Test("U15: applyDatabasePermissions — DB + wal + shm đều 0600; chmod lỗi → PersistenceError")
    func databasePermissions() async throws {
        let url = Self.tempDB()
        defer {
            for path in [url.path, url.path + "-wal", url.path + "-shm"] {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        // Tạo sẵn DB + WAL + SHM giả (helper chỉ cần file tồn tại).
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            try Data("x".utf8).write(to: URL(fileURLWithPath: path))
        }

        try VaultDatabase.applyDatabasePermissions(at: url)
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
            #expect(perms & 0o777 == 0o600, "\(path) phải 0600")
        }

        // FileManager lỗi khi chmod → PersistenceError.database, không nuốt.
        do {
            try VaultDatabase.applyDatabasePermissions(at: url, fileManager: ThrowingAttributesFM())
            Issue.record("phải throw")
        } catch {
            // GRDB xuất typealias deprecated trùng tên PersistenceError nên không cast
            // kiểu được; so khớp qua sample cùng kiểu dựng theo expression (như U13).
            let sample = PersistenceError.database("")
            guard Swift.type(of: error) == Swift.type(of: sample) else {
                Issue.record("kỳ vọng PersistenceError, được \(error)")
                return
            }
            guard String(describing: error).hasPrefix("database(") else {
                Issue.record("kỳ vọng case .database, được \(error)")
                return
            }
        }
    }

    private func writeBatch(_ db: VaultDatabase, tag: String) async throws {
        for i in 0..<100 {
            try await db.writer.write { db in
                try AuditEventRecord(
                    AuditEvent(
                        id: AuditEventID(rawValue: UUID()), actor: .app, action: .tokenIssued,
                        target: "batch:\(tag):\(i)", result: .success, timestamp: Date())
                ).insert(db)
            }
        }
    }
}
