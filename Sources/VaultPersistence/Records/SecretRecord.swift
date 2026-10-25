import Foundation
import GRDB
import VaultDomain

struct SecretRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "secret"

    let id: String
    let kind: String
    let label: String
    let keychainAccount: String
    let requiresUserPresence: Bool
    let createdAt: Double
    let rotatedAt: Double?

    init(row: Row) {
        id = row["id"]
        kind = row["kind"]
        label = row["label"]
        keychainAccount = row["keychain_account"]
        requiresUserPresence = row["requires_user_presence"]
        createdAt = row["created_at"]
        rotatedAt = row["rotated_at"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["kind"] = kind
        container["label"] = label
        container["keychain_account"] = keychainAccount
        container["requires_user_presence"] = requiresUserPresence
        container["created_at"] = createdAt
        container["rotated_at"] = rotatedAt
    }

    init(_ entity: Secret) {
        id = entity.id.rawValue.uuidString.lowercased()
        kind = entity.kind.rawValue
        label = entity.label
        keychainAccount = entity.keychainRef.account
        requiresUserPresence = entity.requiresUserPresence
        createdAt = entity.createdAt.timeIntervalSince1970
        rotatedAt = entity.rotatedAt?.timeIntervalSince1970
    }

    func toEntity() throws -> Secret {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, id: id)
        }
        // DB chỉ lưu account "<kind>.<uuid>"; dựng lại ref và chốt khớp chuỗi lưu.
        let parts = keychainAccount.split(separator: ".", maxSplits: 1)
        guard
            parts.count == 2,
            let kind = SecretKind(rawValue: String(parts[0])),
            let secretUUID = UUID(uuidString: String(parts[1]))
        else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, id: id)
        }
        let ref = KeychainRef(kind: kind, id: SecretID(rawValue: secretUUID))
        guard ref.account == keychainAccount else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, id: id)
        }
        return Secret(
            id: SecretID(rawValue: uuid),
            kind: kind,
            label: label,
            keychainRef: ref,
            requiresUserPresence: requiresUserPresence,
            createdAt: Date(timeIntervalSince1970: createdAt),
            rotatedAt: rotatedAt.map { Date(timeIntervalSince1970: $0) })
    }
}
