import Foundation
import VaultDomain

/// Claims của id_token (OIDC Core §3.1.3.7). Không verify chữ ký (PRODUCT Open Questions) —
/// token chỉ đến từ luồng PKCE + state đã kiểm; header `alg` phải khác `none`.
public struct IDTokenClaims: Sendable, Equatable, Decodable {
    public var iss: String
    public var sub: String
    /// Chấp nhận string hoặc array trong JSON; luôn normalize thành mảng.
    public var aud: [String]
    /// NumericDate (giây).
    public var exp: Date
    public var iat: Date?
    public var email: String?
    public var emailVerified: Bool?
    public var name: String?
    public var preferredUsername: String?
    /// Microsoft tenant.
    public var tid: String?

    enum CodingKeys: String, CodingKey {
        case iss, sub, aud, exp, iat
        case email
        case emailVerified = "email_verified"
        case name
        case preferredUsername = "preferred_username"
        case tid
    }

    public init(
        iss: String,
        sub: String,
        aud: [String],
        exp: Date,
        iat: Date? = nil,
        email: String? = nil,
        emailVerified: Bool? = nil,
        name: String? = nil,
        preferredUsername: String? = nil,
        tid: String? = nil
    ) {
        self.iss = iss
        self.sub = sub
        self.aud = aud
        self.exp = exp
        self.iat = iat
        self.email = email
        self.emailVerified = emailVerified
        self.name = name
        self.preferredUsername = preferredUsername
        self.tid = tid
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iss = try container.decode(String.self, forKey: .iss)
        sub = try container.decode(String.self, forKey: .sub)
        // aud: string hoặc array.
        // try?: aud dạng string là nhánh tùy chọn — sai dạng rơi xuống decode array dưới.
        if let single = try? container.decode(String.self, forKey: .aud) {
            aud = [single]
        } else {
            aud = try container.decode([String].self, forKey: .aud)
        }
        let expSeconds = try container.decode(Double.self, forKey: .exp)
        exp = Date(timeIntervalSince1970: expSeconds)
        iat = try container.decodeIfPresent(Double.self, forKey: .iat)
            .map { Date(timeIntervalSince1970: $0) }
        email = try container.decodeIfPresent(String.self, forKey: .email)
        emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        preferredUsername = try container.decodeIfPresent(String.self, forKey: .preferredUsername)
        tid = try container.decodeIfPresent(String.self, forKey: .tid)
    }

    /// JWT hỏng dạng / alg none / claims thiếu → `.invalidIDToken`.
    public static func decode(_ jwt: String) throws -> IDTokenClaims {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else {
            throw OAuthError.invalidIDToken("JWT phải có đúng 3 phần")
        }
        guard let headerData = Base64URL.decode(String(parts[0])) else {
            throw OAuthError.invalidIDToken("header không decode được")
        }
        // try?: header là JSON tùy chọn — hỏng thì báo invalidIDToken ngay dưới.
        guard let header = try? JSONDecoder().decode(Header.self, from: headerData) else {
            throw OAuthError.invalidIDToken("header không decode được")
        }
        guard header.alg.caseInsensitiveCompare("none") != .orderedSame else {
            throw OAuthError.invalidIDToken("alg none không được chấp nhận")
        }
        guard let payloadData = Base64URL.decode(String(parts[1])) else {
            throw OAuthError.invalidIDToken("payload không decode được")
        }
        do {
            return try JSONDecoder().decode(IDTokenClaims.self, from: payloadData)
        } catch {
            throw OAuthError.invalidIDToken("claims: \(error.localizedDescription)")
        }
    }

    private struct Header: Decodable {
        let alg: String
    }

    public func validate(
        provider: Provider, clientId: String, now: Date, leeway: TimeInterval = 300
    ) throws {
        guard aud.contains(clientId) else {
            throw OAuthError.invalidIDToken("aud không chứa client_id")
        }
        guard exp.timeIntervalSince(now) + leeway > 0 else {
            throw OAuthError.invalidIDToken("token đã hết hạn")
        }
        if provider.quirks.issuerIsTenantTemplated {
            guard let tid, !tid.isEmpty else {
                throw OAuthError.invalidIDToken("issuer dạng template nhưng thiếu tid")
            }
            let expected = provider.issuer.replacingOccurrences(of: "{tenantid}", with: tid)
            guard iss == expected else {
                throw OAuthError.issuerMismatch(expected: expected, actual: iss)
            }
        } else {
            guard iss == provider.issuer else {
                throw OAuthError.issuerMismatch(expected: provider.issuer, actual: iss)
            }
        }
    }

    public var bestEmail: String? { email ?? preferredUsername }
}
