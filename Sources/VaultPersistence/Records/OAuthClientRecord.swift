import Foundation
import GRDB
import VaultDomain

struct OAuthClientRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "oauth_client"

    let id: String
    let providerId: String
    let clientId: String
    let clientSecretRef: String?
    let redirectURI: String
    let secretExpiresAt: Double?
    let label: String
    let createdAt: Double

    init(row: Row) {
        id = row["id"]
        providerId = row["provider_id"]
        clientId = row["client_id"]
        clientSecretRef = row["client_secret_ref"]
        redirectURI = row["redirect_uri"]
        secretExpiresAt = row["secret_expires_at"]
        label = row["label"]
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["provider_id"] = providerId
        container["client_id"] = clientId
        container["client_secret_ref"] = clientSecretRef
        container["redirect_uri"] = redirectURI
        container["secret_expires_at"] = secretExpiresAt
        container["label"] = label
        container["created_at"] = createdAt
    }

    init(_ entity: OAuthClient) {
        id = entity.id.rawValue.uuidString.lowercased()
        providerId = entity.providerId.rawValue
        clientId = entity.clientId
        clientSecretRef = entity.clientSecretRef?.rawValue.uuidString.lowercased()
        redirectURI = entity.redirectURI.absoluteString
        secretExpiresAt = entity.secretExpiresAt?.timeIntervalSince1970
        label = entity.label
        createdAt = entity.createdAt.timeIntervalSince1970
    }

    func toEntity() throws -> OAuthClient {
        func fail() -> PersistenceError {
            .corruptRow(table: Self.databaseTableName, id: id)
        }
        guard
            let uuid = UUID(uuidString: id),
            let provider = ProviderID(rawValue: providerId),
            let redirect = URL(string: redirectURI)
        else { throw fail() }
        let secretRef = try clientSecretRef.map { ref -> SecretID in
            guard let s = UUID(uuidString: ref) else { throw fail() }
            return SecretID(rawValue: s)
        }
        return OAuthClient(
            id: OAuthClientID(rawValue: uuid),
            providerId: provider,
            clientId: clientId,
            clientSecretRef: secretRef,
            redirectURI: redirect,
            secretExpiresAt: secretExpiresAt.map { Date(timeIntervalSince1970: $0) },
            label: label,
            createdAt: Date(timeIntervalSince1970: createdAt))
    }
}
