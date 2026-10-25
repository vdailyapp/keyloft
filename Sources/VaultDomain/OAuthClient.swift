import Foundation

public struct OAuthClient: Codable, Sendable, Equatable, Identifiable {
    public let id: OAuthClientID
    public var providerId: ProviderID
    public var clientId: String
    /// nil = public client (PKCE only, không có secret).
    public var clientSecretRef: SecretID?
    /// `http://127.0.0.1/callback` (không port = cổng ngẫu nhiên) hoặc có port cố định.
    public var redirectURI: URL
    public var secretExpiresAt: Date?
    public var label: String
    public var createdAt: Date

    public init(
        id: OAuthClientID,
        providerId: ProviderID,
        clientId: String,
        clientSecretRef: SecretID?,
        redirectURI: URL,
        secretExpiresAt: Date? = nil,
        label: String,
        createdAt: Date
    ) {
        self.id = id
        self.providerId = providerId
        self.clientId = clientId
        self.clientSecretRef = clientSecretRef
        self.redirectURI = redirectURI
        self.secretExpiresAt = secretExpiresAt
        self.label = label
        self.createdAt = createdAt
    }
}
