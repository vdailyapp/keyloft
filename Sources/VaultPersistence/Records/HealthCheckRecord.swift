import Foundation
import GRDB
import VaultDomain

struct HealthCheckRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "health_check_result"

    let id: String
    let accountId: String
    let checkedAt: Double
    let status: String
    let checks: String

    init(row: Row) {
        id = row["id"]
        accountId = row["account_id"]
        checkedAt = row["checked_at"]
        status = row["status"]
        checks = row["checks"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["account_id"] = accountId
        container["checked_at"] = checkedAt
        container["status"] = status
        container["checks"] = checks
    }

    init(_ entity: HealthCheckResult) throws {
        id = entity.id.rawValue.uuidString.lowercased()
        accountId = entity.accountId.rawValue.uuidString.lowercased()
        checkedAt = entity.checkedAt.timeIntervalSince1970
        status = entity.status.rawValue
        checks = try RecordJSON.encode(entity.checks)
    }

    func toEntity() throws -> HealthCheckResult {
        guard
            let uuid = UUID(uuidString: id),
            let accountUUID = UUID(uuidString: accountId),
            let status = AccountStatus(rawValue: status)
        else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, id: id)
        }
        let items = try RecordJSON.decode([HealthCheckItem].self, from: checks)
        return HealthCheckResult(
            id: HealthCheckID(rawValue: uuid),
            accountId: AccountID(rawValue: accountUUID),
            checkedAt: Date(timeIntervalSince1970: checkedAt),
            status: status,
            checks: items)
    }
}
