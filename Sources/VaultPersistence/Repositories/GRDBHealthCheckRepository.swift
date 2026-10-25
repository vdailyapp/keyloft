import Foundation
import GRDB
import VaultDomain

public struct GRDBHealthCheckRepository: HealthCheckRepository {
    let db: VaultDatabase

    public init(db: VaultDatabase) { self.db = db }

    public func append(_ result: HealthCheckResult) async throws {
        try await db.write { db in
            try HealthCheckRecord(result).insert(db)
            // Giữ đúng 50 bản mới nhất mỗi account (SPEC-003 §4).
            try db.execute(
                sql: """
                    DELETE FROM health_check_result
                    WHERE account_id = ?
                      AND id NOT IN (
                        SELECT id FROM health_check_result
                        WHERE account_id = ?
                        ORDER BY checked_at DESC, id DESC
                        LIMIT ?
                      )
                    """,
                arguments: [
                    result.accountId.rawValue.uuidString.lowercased(),
                    result.accountId.rawValue.uuidString.lowercased(),
                    HealthCheckRetention.perAccount,
                ])
        }
    }

    public func latest(for account: AccountID) async throws -> HealthCheckResult? {
        try await db.read { db in
            try HealthCheckRecord
                .filter(Column("account_id") == account.rawValue.uuidString.lowercased())
                .order(Column("checked_at").desc, Column("id").desc)
                .fetchOne(db)?.toEntity()
        }
    }

    public func list(for account: AccountID, limit: Int) async throws -> [HealthCheckResult] {
        try await db.read { db in
            try HealthCheckRecord
                .filter(Column("account_id") == account.rawValue.uuidString.lowercased())
                .order(Column("checked_at").desc, Column("id").desc)
                .limit(limit)
                .fetchAll(db).map { try $0.toEntity() }
        }
    }
}
