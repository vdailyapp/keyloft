import Foundation
import VaultDomain

public struct DiscoveryDocument: Sendable, Equatable, Codable {
    public var issuer: String
    public var authorizationEndpoint: URL
    public var tokenEndpoint: URL
    public var revocationEndpoint: URL?
    public var authorizationResponseIssParameterSupported: Bool?
    public var codeChallengeMethodsSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case authorizationResponseIssParameterSupported =
            "authorization_response_iss_parameter_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }

    public init(
        issuer: String,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        revocationEndpoint: URL? = nil,
        authorizationResponseIssParameterSupported: Bool? = nil,
        codeChallengeMethodsSupported: [String]? = nil
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.revocationEndpoint = revocationEndpoint
        self.authorizationResponseIssParameterSupported =
            authorizationResponseIssParameterSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
    }
}

public enum ProviderError: Error, Sendable, Equatable {
    case discovery(String)
}

public struct OIDCDiscovery: Sendable {
    private let http: any HTTPClient

    public init(http: any HTTPClient) {
        self.http = http
    }

    public func fetch(_ url: URL) async throws -> DiscoveryDocument {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await http.send(request)
            guard (200...299).contains(response.statusCode) else {
                throw ProviderError.discovery("HTTP \(response.statusCode)")
            }
            return try JSONDecoder().decode(DiscoveryDocument.self, from: data)
        } catch let error as ProviderError {
            throw error
        } catch let error as URLError {
            throw ProviderError.discovery("mạng: \(error.code.rawValue)")
        } catch {
            throw ProviderError.discovery("decode: \(error.localizedDescription)")
        }
    }

    /// Trộn an toàn: issuer phải khớp nguyên chuỗi (kể cả template Microsoft) — khác thì
    /// bỏ doc (chống discovery giả mạo); không có S256 → bỏ doc. Chỉ đổi endpoint/issuer/cờ
    /// iss, mọi quirks khác giữ nguyên.
    public static func merge(_ provider: Provider, _ doc: DiscoveryDocument) -> Provider {
        guard doc.issuer == provider.issuer else { return provider }
        if let methods = doc.codeChallengeMethodsSupported, !methods.contains("S256") {
            return provider
        }
        var quirks = provider.quirks
        if let issSupported = doc.authorizationResponseIssParameterSupported {
            quirks.authorizationResponseIssSupported = issSupported
        }
        return Provider(
            id: provider.id,
            displayName: provider.displayName,
            issuer: doc.issuer,
            authURL: doc.authorizationEndpoint,
            tokenURL: doc.tokenEndpoint,
            revokeURL: doc.revocationEndpoint ?? provider.revokeURL,
            discoveryURL: provider.discoveryURL,
            defaultScopes: provider.defaultScopes,
            extraAuthParams: provider.extraAuthParams,
            quirks: quirks)
    }
}
