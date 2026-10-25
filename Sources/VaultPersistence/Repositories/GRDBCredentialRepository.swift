import Foundation
import GRDB
import VaultDomain

public struct GRDBCredentialRepository: CredentialRepository {
    let db: VaultDatabase

    public init(db: VaultDatabase) { self.db = db }

    public func insert(_ credential: Credential) async throws {
        try await db.write { try CredentialRecord(credential).insert($0) }
    }

    public func get(_ id: CredentialID) async throws -> Credential? {
        try await db.read { try CredentialRecord.fetchOne($0, key: id.rawValue.uuidString.lowercased())?.toEntity() }
    }

    public func active(for account: AccountID) async throws -> Credential? {
        try await db.read { db in
            try CredentialRecord
                .filter(Column("account_id") == account.rawValue.uuidString.lowercased())
                .filter(Column("status") == CredentialStatus.active.rawValue)
                .order(Column("issued_at").desc)
                .fetchOne(db)?.toEntity()
        }
    }

    public func list(for account: AccountID) async throws -> [Credential] {
        try await db.read { db in
            try CredentialRecord
                .filter(Column("account_id") == account.rawValue.uuidString.lowercased())
                .order(Column("issued_at"))
                .fetchAll(db).map { try $0.toEntity() }
        }
    }

    public func markSuperseded(_ id: CredentialID, by newId: CredentialID) async throws {
        try await db.write { db in
            let key = id.rawValue.uuidString.lowercased()
            guard try CredentialRecord.fetchOne(db, key: key) != nil else {
                throw DomainError.notFound("credential:\(id)")
            }
            try db.execute(
                sql: "UPDATE credential SET status = ?, superseded_by = ? WHERE id = ?",
                arguments: [
                    CredentialStatus.superseded.rawValue, newId.rawValue.uuidString.lowercased(), key,
                ])
        }
    }

    public func markRevoked(_ id: CredentialID) async throws {
        try await db.write { db in
            let key = id.rawValue.uuidString.lowercased()
            guard try CredentialRecord.fetchOne(db, key: key) != nil else {
                throw DomainError.notFound("credential:\(id)")
            }
            try db.execute(
                sql: "UPDATE credential SET status = ? WHERE id = ?",
                arguments: [CredentialStatus.revoked.rawValue, key])
        }
    }

    public func updateGrantedScopes(_ id: CredentialID, _ scopes: ScopeSet) async throws {
        try await db.write { db in
            let key = id.rawValue.uuidString.lowercased()
            guard try CredentialRecord.fetchOne(db, key: key) != nil else {
                throw DomainError.notFound("credential:\(id)")
            }
            try db.execute(
                sql: "UPDATE credential SET granted_scopes = ? WHERE id = ?",
                arguments: [try RecordJSON.encode(scopes), key])
        }
    }
}
