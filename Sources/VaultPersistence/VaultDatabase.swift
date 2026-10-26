import Foundation
import GRDB
import VaultDomain

/// Cửa vào SQLite: mở DB file (hoặc in-memory cho test), cấu hình an toàn và migrate.
/// `writer` là `DatabasePool` (file, WAL) hoặc `DatabaseQueue` (memory).
public final class VaultDatabase: Sendable {
    public let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// `~/Library/Application Support/app.vdaily.keyloft/vault.sqlite`.
    public static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("app.vdaily.keyloft", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("vault.sqlite")
    }

    /// Mở DB file: thư mục 0700, file 0600, WAL, FK on, busy timeout 5 s, migrate.
    public static func open(at url: URL) throws -> VaultDatabase {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        var config = Configuration()
        config.foreignKeysEnabled = true
        config.busyMode = .timeout(5)
        // WAL chỉ áp dụng cho DB file (in-memory không đặt được).
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        let database = VaultDatabase(writer: pool)
        do {
            try database.migrate()
        } catch {
            // try?: đóng pool khi migrate lỗi — best-effort dọn tài nguyên, không che lỗi gốc.
            try? pool.close()
            throw error
        }
        try applyDatabasePermissions(at: url)
        return database
    }

    /// Quyền 0600 cho DB + `-wal`/`-shm` (nếu đã tồn tại): chmod lỗi nghĩa là DB vẫn mở
    /// với quyền rộng — phải throw, không được bỏ qua.
    static func applyDatabasePermissions(at url: URL, fileManager: FileManager = .default) throws {
        for path in [url.path, url.path + "-wal", url.path + "-shm"]
        where fileManager.fileExists(atPath: path) {
            do {
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            } catch {
                throw PersistenceError.database(
                    "không đặt quyền 0600 cho \(URL(fileURLWithPath: path).lastPathComponent): \(error)")
            }
        }
    }

    public static func inMemory() throws -> VaultDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        let database = VaultDatabase(writer: queue)
        try database.migrate()
        return database
    }

    /// Phát hiện schema mới hơn code: `grdb_migrations` có identifier lạ (vd `"v99_future"`)
    /// → từ chối mở thay vì ghi hỏng thêm.
    private func migrate() throws {
        let migrator = Self.migrator
        try writer.writeWithoutTransaction { db in
            if try migrator.hasBeenSuperseded(db) {
                throw PersistenceError.schemaTooNew
            }
        }
        try migrator.migrate(writer)
    }
}
