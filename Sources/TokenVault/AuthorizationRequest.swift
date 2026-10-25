import Foundation
import VaultDomain

/// Request authorize dựng URL theo thứ tự tham số cố định (để test phát hiện thay đổi
/// tham số gửi lên provider). Percent-encode RFC 3986: space → `%20` (không dùng `+`).
public struct AuthorizationRequest: Sendable {
    public var provider: Provider
    public var clientId: String
    public var redirectURI: URL
    public var scopes: ScopeSet
    public var state: String
    public var pkce: PKCEPair
    public var loginHint: String?
    public var includeGrantedScopes: Bool = false

    public init(
        provider: Provider,
        clientId: String,
        redirectURI: URL,
        scopes: ScopeSet,
        state: String,
        pkce: PKCEPair,
        loginHint: String? = nil,
        includeGrantedScopes: Bool = false
    ) {
        self.provider = provider
        self.clientId = clientId
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.state = state
        self.pkce = pkce
        self.loginHint = loginHint
        self.includeGrantedScopes = includeGrantedScopes
    }

    /// Tham số bảo mật không được ghi đè bằng `extraAuthParams`.
    static let protectedKeys: Set<String> = [
        "response_type", "client_id", "redirect_uri", "scope", "state",
        "code_challenge", "code_challenge_method",
    ]

    public func url() throws -> URL {
        for key in provider.extraAuthParams.keys where Self.protectedKeys.contains(key) {
            throw DomainError.invariantViolated("extraAuthParams không được chứa key bảo mật: \(key)")
        }

        var query =
            [
                ("response_type", "code"),
                ("client_id", clientId),
                ("redirect_uri", redirectURI.absoluteString),
                ("scope", scopes.spaceDelimited),
                ("state", state),
                ("code_challenge", pkce.challenge),
                ("code_challenge_method", pkce.method),
            ]
            + provider.extraAuthParams
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }

        if includeGrantedScopes {
            query.append(("include_granted_scopes", "true"))
        }
        if let loginHint {
            query.append(("login_hint", loginHint))
        }

        var components = URLComponents()
        components.scheme = provider.authURL.scheme
        components.host = provider.authURL.host
        components.port = provider.authURL.port
        // Path đã percent-safe từ URL gốc; query tự encode bằng bộ unreserved RFC 3986.
        components.percentEncodedPath = provider.authURL.path.isEmpty ? "/" : provider.authURL.path
        components.percentEncodedQuery =
            query
            .map { "\(Self.encode($0.0))=\(Self.encode($0.1))" }
            .joined(separator: "&")

        guard let url = components.url else {
            throw DomainError.invariantViolated("không dựng được authorize URL cho \(provider.id)")
        }
        return url
    }

    /// RFC 3986: giữ unreserved `A-Z a-z 0-9 - . _ ~`, còn lại `%XX` hoa.
    static func encode(_ value: String) -> String {
        var output = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "-", ".", "_", "~":
                output.unicodeScalars.append(scalar)
            default:
                for byte in String(scalar).utf8 {
                    output += String(format: "%%%02X", byte)
                }
            }
        }
        return output
    }
}
