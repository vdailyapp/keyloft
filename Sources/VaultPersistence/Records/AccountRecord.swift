import Foundation
import GRDB
import VaultDomain

struct AccountRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "account"

    let id: String
    let providerId: String
    let oauthClientId: String
    let externalId: String
    let email: String?
    let displayName: String?
    let status: String
    let statusChangedAt: Double
    let createdAt: Double

    init(row: Row) {
        id = row["id"]
        providerId = row["provider_id"]
        oauthClientId = row["oauth_client_id"]
        externalId = row["external_id"]
        email = row["email"]
        displayName = row["display_name"]
        status = row["status"]
        statusChangedAt = row["status_changed_at"]
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["provider_id"] = providerId
        container["oauth_client_id"] = oauthClientId
        container["external_id"] = externalId
        container["email"] = email
        container["display_name"] = displayName
        container["status"] = status
        container["status_changed_at"] = statusChangedAt
        container["created_at"] = createdAt
    }

    init(_ entity: Account) {
        id = entity.id.rawValue.uuidString.lowercased()
        providerId = entity.providerId.rawValue
        oauthClientId = entity.oauthClientId.rawValue.uuidString.lowercased()
        externalId = entity.externalId
        email = entity.email
        displayName = entity.displayName
        status = entity.status.rawValue
        statusChangedAt = entity.statusChangedAt.timeIntervalSince1970
        createdAt = entity.createdAt.timeIntervalSince1970
    }

    func toEntity() throws -> Account {
        guard
            let uuid = UUID(uuidString: id),
            let clientUUID = UUID(uuidString: oauthClientId),
            let provider = ProviderID(rawValue: providerId),
            let status = AccountStatus(rawValue: status)
        else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, id: id)
        }
        return Account(
            id: AccountID(rawValue: uuid),
            providerId: provider,
            oauthClientId: OAuthClientID(rawValue: clientUUID),
            externalId: externalId,
            email: email,
            displayName: displayName,
            status: status,
            statusChangedAt: Date(timeIntervalSince1970: statusChangedAt),
            createdAt: Date(timeIntervalSince1970: createdAt))
    }
}
