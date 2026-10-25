import Foundation

public struct Account: Codable, Sendable, Equatable, Identifiable {
    public let id: AccountID
    public var providerId: ProviderID
    public var oauthClientId: OAuthClientID
    /// `id_token.sub` — định danh ổn định (email có thể đổi).
    public var externalId: String
    public var email: String?
    public var displayName: String?
    public var status: AccountStatus
    public var statusChangedAt: Date
    public var createdAt: Date

    public init(
        id: AccountID,
        providerId: ProviderID,
        oauthClientId: OAuthClientID,
        externalId: String,
        email: String? = nil,
        displayName: String? = nil,
        status: AccountStatus,
        statusChangedAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.providerId = providerId
        self.oauthClientId = oauthClientId
        self.externalId = externalId
        self.email = email
        self.displayName = displayName
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.createdAt = createdAt
    }
}
