import Foundation
import GRDB
import VaultDomain

public struct GRDBSecretMetadataRepository: SecretMetadataRepository {
    let db: VaultDatabase

    public init(db: VaultDatabase) { self.db = db }

    public func insert(_ secret: Secret) async throws {
        try await db.write { try SecretRecord(secret).insert($0) }
    }

    public func get(_ id: SecretID) async throws -> Secret? {
        try await db.read { try SecretRecord.fetchOne($0, key: id.rawValue.uuidString.lowercased())?.toEntity() }
    }

    public func list(kind: SecretKind?) async throws -> [Secret] {
        try await db.read { db in
            var request = SecretRecord.order(Column("created_at"))
            if let kind {
                request = request.filter(Column("kind") == kind.rawValue)
            }
            return try request.fetchAll(db).map { try $0.toEntity() }
        }
    }

    public func markRotated(_ id: SecretID, at date: Date) async throws {
        try await db.write { db in
            let key = id.rawValue.uuidString.lowercased()
            guard try SecretRecord.fetchOne(db, key: key) != nil else {
                throw DomainError.notFound("secret:\(id)")
            }
            try db.execute(
                sql: "UPDATE secret SET rotated_at = ? WHERE id = ?",
                arguments: [date.timeIntervalSince1970, key])
        }
    }

    public func delete(_ id: SecretID) async throws {
        try await db.write { db in
            let key = id.rawValue.uuidString.lowercased()
            // credential.refresh_token_ref ON DELETE RESTRICT — báo lỗi miền rõ ràng hơn FK.
            let dependents =
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM credential WHERE refresh_token_ref = ?",
                    arguments: [key]) ?? 0
            if dependents > 0 {
                throw DomainError.hasDependents("secret:\(id)")
            }
            try SecretRecord.deleteOne(db, key: key)
        }
    }
}
