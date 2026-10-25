import Foundation
import GRDB
import VaultDomain

struct CredentialRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "credential"

    let id: String
    let accountId: String
    let refreshTokenRef: String
    let requestedScopes: String
    let grantedScopes: String
    let issuedAt: Double
    let supersededBy: String?
    let status: String

    init(row: Row) {
        id = row["id"]
        accountId = row["account_id"]
        refreshTokenRef = row["refresh_token_ref"]
        requestedScopes = row["requested_scopes"]
        grantedScopes = row["granted_scopes"]
        issuedAt = row["issued_at"]
        supersededBy = row["superseded_by"]
        status = row["status"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["account_id"] = accountId
        container["refresh_token_ref"] = refreshTokenRef
        container["requested_scopes"] = requestedScopes
        container["granted_scopes"] = grantedScopes
        container["issued_at"] = issuedAt
        container["superseded_by"] = supersededBy
        container["status"] = status
    }

    init(_ entity: Credential) throws {
        id = entity.id.rawValue.uuidString.lowercased()
        accountId = entity.accountId.rawValue.uuidString.lowercased()
        refreshTokenRef = entity.refreshTokenRef.rawValue.uuidString.lowercased()
        requestedScopes = try RecordJSON.encode(entity.requestedScopes)
        grantedScopes = try RecordJSON.encode(entity.grantedScopes)
        issuedAt = entity.issuedAt.timeIntervalSince1970
        supersededBy = entity.supersededBy?.rawValue.uuidString.lowercased()
        status = entity.status.rawValue
    }

    func toEntity() throws -> Credential {
        func fail() -> PersistenceError {
            .corruptRow(table: Self.databaseTableName, id: id)
        }
        guard
            let uuid = UUID(uuidString: id),
            let accountUUID = UUID(uuidString: accountId),
            let secretUUID = UUID(uuidString: refreshTokenRef),
            let status = CredentialStatus(rawValue: status)
        else { throw fail() }
        let requested = try RecordJSON.decode(ScopeSet.self, from: requestedScopes)
        let granted = try RecordJSON.decode(ScopeSet.self, from: grantedScopes)
        let superseder = try supersededBy.map { s -> CredentialID in
            guard let u = UUID(uuidString: s) else { throw fail() }
            return CredentialID(rawValue: u)
        }
        return Credential(
            id: CredentialID(rawValue: uuid),
            accountId: AccountID(rawValue: accountUUID),
            refreshTokenRef: SecretID(rawValue: secretUUID),
            requestedScopes: requested,
            grantedScopes: granted,
            issuedAt: Date(timeIntervalSince1970: issuedAt),
            supersededBy: superseder,
            status: status)
    }
}
