import Foundation

public enum AuditActor: String, Codable, Sendable {
    case user, app, cli, scheduler
}

public enum AuditAction: String, Codable, Sendable {
    case accountAdded = "account.added"
    case accountRemoved = "account.removed"
    case accountStatusChanged = "account.status_changed"
    case credentialIssued = "credential.issued"
    case credentialSuperseded = "credential.superseded"
    case credentialRevoked = "credential.revoked"
    case tokenRefreshed = "token.refreshed"
    case tokenRefreshFailed = "token.refresh_failed"
    case tokenIssued = "token.issued"
    case scopeGranted = "scope.granted"
    case scopeDenied = "scope.denied"
    case scopeReduced = "scope.reduced"
    case secretCreated = "secret.created"
    case secretRead = "secret.read"
    case secretRotated = "secret.rotated"
    case secretDeleted = "secret.deleted"
    case oauthClientCreated = "oauth_client.created"
    case oauthClientDeleted = "oauth_client.deleted"
}

public enum AuditResult: Codable, Sendable, Equatable {
    case success
    case failure(reason: String)
}

public struct AuditEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: AuditEventID
    public var actor: AuditActor
    public var action: AuditAction
    /// "account:<id>", "credential:<id>", "secret:<id>"...
    public var target: String
    public var scopes: ScopeSet?
    public var result: AuditResult
    public var timestamp: Date

    public init(
        id: AuditEventID,
        actor: AuditActor,
        action: AuditAction,
        target: String,
        scopes: ScopeSet? = nil,
        result: AuditResult,
        timestamp: Date
    ) {
        self.id = id
        self.actor = actor
        self.action = action
        self.target = target
        self.scopes = scopes
        self.result = result
        self.timestamp = timestamp
    }
}
