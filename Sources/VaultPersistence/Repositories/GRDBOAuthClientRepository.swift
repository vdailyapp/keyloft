import Foundation
import GRDB
import VaultDomain

// Helper dùng chung cho mọi repo GRDB: lỗi miền giữ nguyên, lỗi GRDB bọc
// `PersistenceError.database`. Đặt ở file đầu tiên của Repositories/ cho gọn.
extension VaultDatabase {
    func write<T>(_ body: (Database) throws -> T) async throws -> T {
        do {
            return try await writer.write(body)
        } catch let error as DomainError {
            throw error
        } catch let error as PersistenceError {
            throw error
        } catch let error as DatabaseError {
            throw PersistenceError.database(error.message ?? "\(error)")
        }
    }

    func read<T>(_ body: (Database) throws -> T) async throws -> T {
        do {
            return try await writer.read(body)
        } catch let error as DomainError {
            throw error
        } catch let error as PersistenceError {
            throw error
        } catch let error as DatabaseError {
            throw PersistenceError.database(error.message ?? "\(error)")
        }
    }
}

public struct GRDBOAuthClientRepository: OAuthClientRepository {
    let db: VaultDatabase

    public init(db: VaultDatabase) { self.db = db }

    public func save(_ client: OAuthClient) async throws {
        try await db.write { try OAuthClientRecord(client).save($0) }
    }

    public func get(_ id: OAuthClientID) async throws -> OAuthClient? {
        try await db.read { try OAuthClientRecord.fetchOne($0, key: id.rawValue.uuidString.lowercased())?.toEntity() }
    }

    public func list(provider: ProviderID?) async throws -> [OAuthClient] {
        try await db.read { db in
            var request = OAuthClientRecord.order(Column("created_at"))
            if let provider {
                request = request.filter(Column("provider_id") == provider.rawValue)
            }
            return try request.fetchAll(db).map { try $0.toEntity() }
        }
    }

    public func delete(_ id: OAuthClientID) async throws {
        try await db.write { db in
            let key = id.rawValue.uuidString.lowercased()
            let accounts =
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM account WHERE oauth_client_id = ?", arguments: [key]) ?? 0
            if accounts > 0 {
                throw DomainError.hasDependents("oauth_client:\(id)")
            }
            try OAuthClientRecord.deleteOne(db, key: key)
        }
    }
}
