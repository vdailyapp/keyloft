import Foundation
import GRDB
import VaultDomain

/// Audit log chỉ ghi thêm (trigger DB chặn UPDATE/DELETE — xem U9 SPEC-003).
public struct GRDBAuditLog: AuditLog {
    let db: VaultDatabase

    public init(db: VaultDatabase) { self.db = db }

    public func append(_ event: AuditEvent) async throws {
        try await db.write { try AuditEventRecord(event).insert($0) }
    }

    public func query(_ query: AuditQuery) async throws -> [AuditEvent] {
        try await db.read { db in
            var conditions: [String] = []
            var arguments: [any DatabaseValueConvertible] = []
            if let target = query.target {
                conditions.append("target = ?")
                arguments.append(target)
            }
            if let actions = query.actions, !actions.isEmpty {
                let placeholders = Array(repeating: "?", count: actions.count).joined(separator: ",")
                conditions.append("action IN (\(placeholders))")
                arguments.append(contentsOf: actions.map(\.rawValue))
            }
            if let since = query.since {
                conditions.append("timestamp >= ?")
                arguments.append(since.timeIntervalSince1970)
            }
            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let sql = "SELECT * FROM audit_event \(whereClause) ORDER BY timestamp DESC, id DESC LIMIT ?"
            arguments.append(query.limit)
            return
                try AuditEventRecord
                .fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                .map { try $0.toEntity() }
        }
    }
}
