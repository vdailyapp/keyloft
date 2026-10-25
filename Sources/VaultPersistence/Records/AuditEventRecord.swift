import Foundation
import GRDB
import VaultDomain

struct AuditEventRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "audit_event"

    let id: String
    let actor: String
    let action: String
    let target: String
    let scopes: String?
    let result: String
    let timestamp: Double

    init(row: Row) {
        id = row["id"]
        actor = row["actor"]
        action = row["action"]
        target = row["target"]
        scopes = row["scopes"]
        result = row["result"]
        timestamp = row["timestamp"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["actor"] = actor
        container["action"] = action
        container["target"] = target
        container["scopes"] = scopes
        container["result"] = result
        container["timestamp"] = timestamp
    }

    init(_ entity: AuditEvent) throws {
        id = entity.id.rawValue.uuidString.lowercased()
        actor = entity.actor.rawValue
        action = entity.action.rawValue
        target = entity.target
        scopes = try entity.scopes.map { try RecordJSON.encode($0) }
        result = try RecordJSON.encode(entity.result)
        timestamp = entity.timestamp.timeIntervalSince1970
    }

    func toEntity() throws -> AuditEvent {
        guard
            let uuid = UUID(uuidString: id),
            let actor = AuditActor(rawValue: actor),
            let action = AuditAction(rawValue: action)
        else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, id: id)
        }
        let auditResult = try RecordJSON.decode(AuditResult.self, from: result)
        let scopeSet = try scopes.map { try RecordJSON.decode(ScopeSet.self, from: $0) }
        return AuditEvent(
            id: AuditEventID(rawValue: uuid),
            actor: actor,
            action: action,
            target: target,
            scopes: scopeSet,
            result: auditResult,
            timestamp: Date(timeIntervalSince1970: timestamp))
    }
}
