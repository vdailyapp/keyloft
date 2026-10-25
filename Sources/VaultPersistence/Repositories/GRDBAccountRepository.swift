import Foundation
import GRDB
import VaultDomain

public struct GRDBAccountRepository: AccountRepository {
    let db: VaultDatabase

    public init(db: VaultDatabase) { self.db = db }

    public func save(_ account: Account) async throws {
        try await db.write { try AccountRecord(account).save($0) }
    }

    public func get(_ id: AccountID) async throws -> Account? {
        try await db.read { try AccountRecord.fetchOne($0, key: id.rawValue.uuidString.lowercased())?.toEntity() }
    }

    public func find(
        provider: ProviderID, oauthClient: OAuthClientID, externalId: String
    ) async throws -> Account? {
        try await db.read { db in
            try AccountRecord
                .filter(Column("provider_id") == provider.rawValue)
                .filter(Column("oauth_client_id") == oauthClient.rawValue.uuidString.lowercased())
                .filter(Column("external_id") == externalId)
                .fetchOne(db)?.toEntity()
        }
    }

    public func list() async throws -> [Account] {
        try await db.read { db in
            try AccountRecord.order(Column("created_at")).fetchAll(db).map { try $0.toEntity() }
        }
    }

    public func updateStatus(_ id: AccountID, to status: AccountStatus, at date: Date) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE account SET status = ?, status_changed_at = ? WHERE id = ?",
                arguments: [status.rawValue, date.timeIntervalSince1970, id.rawValue.uuidString.lowercased()])
            if db.changesCount == 0 {
                throw DomainError.notFound("account:\(id)")
            }
        }
    }

    public func delete(_ id: AccountID) async throws {
        try await db.write { db in
            let key = id.rawValue.uuidString.lowercased()
            try db.execute(sql: "DELETE FROM account WHERE id = ?", arguments: [key])
            if db.changesCount == 0 {
                throw DomainError.notFound("account:\(id)")
            }
            // credential + health_check_result tự xóa theo ON DELETE CASCADE.
        }
    }
}
