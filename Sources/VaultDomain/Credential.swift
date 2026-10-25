import Foundation

/// Một grant OAuth thành công = một Credential. Scope gắn với Credential, không gắn Account.
public struct Credential: Codable, Sendable, Equatable, Identifiable {
    public let id: CredentialID
    public var accountId: AccountID
    public var refreshTokenRef: SecretID
    public var requestedScopes: ScopeSet
    public var grantedScopes: ScopeSet
    public var issuedAt: Date
    public var supersededBy: CredentialID?
    public var status: CredentialStatus

    public init(
        id: CredentialID,
        accountId: AccountID,
        refreshTokenRef: SecretID,
        requestedScopes: ScopeSet,
        grantedScopes: ScopeSet,
        issuedAt: Date,
        supersededBy: CredentialID? = nil,
        status: CredentialStatus
    ) {
        self.id = id
        self.accountId = accountId
        self.refreshTokenRef = refreshTokenRef
        self.requestedScopes = requestedScopes
        self.grantedScopes = grantedScopes
        self.issuedAt = issuedAt
        self.supersededBy = supersededBy
        self.status = status
    }
}
