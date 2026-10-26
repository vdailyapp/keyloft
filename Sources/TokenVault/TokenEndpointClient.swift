import Foundation
import VaultDomain

public struct TokenResponse: Sendable, Equatable, Decodable, CustomStringConvertible {
    public var accessToken: String
    public var tokenType: String
    public var expiresIn: Int?
    public var refreshToken: String?
    public var scope: String?
    public var idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case idToken = "id_token"
    }

    public var description: String {
        "TokenResponse(accessToken: <redacted>, tokenType: \(tokenType), "
            + "expiresIn: \(expiresIn.map(String.init) ?? "nil"), "
            + "refreshToken: \(refreshToken != nil ? "<redacted>" : "nil"), "
            + "scope: \(scope ?? "nil"), idToken: \(idToken != nil ? "<redacted>" : "nil"))"
    }
}

public struct ClientCredentials: Sendable {
    public var clientId: String
    public var clientSecret: String?
    public var method: TokenEndpointAuthMethod

    public init(clientId: String, clientSecret: String?, method: TokenEndpointAuthMethod) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.method = method
    }
}

/// Gọi token endpoint: exchange code, refresh, revoke (RFC 6749 §4.1.3/§6, RFC 7009).
public struct TokenEndpointClient: Sendable {
    private let http: any HTTPClient

    public init(http: any HTTPClient) {
        self.http = http
    }

    public func exchangeCode(
        _ code: String,
        verifier: String,
        redirectURI: URL,
        tokenURL: URL,
        client: ClientCredentials
    ) async throws -> TokenResponse {
        var form: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI.absoluteString),
            ("code_verifier", verifier),
            ("client_id", client.clientId),
        ]
        appendClientSecretToForm(&form, client: client)
        return try await post(form: form, url: tokenURL, client: client)
    }

    public func refresh(
        _ refreshToken: String,
        tokenURL: URL,
        client: ClientCredentials,
        scopes: ScopeSet? = nil
    ) async throws -> TokenResponse {
        var form: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", client.clientId),
        ]
        if let scopes {
            form.append(("scope", scopes.spaceDelimited))
        }
        appendClientSecretToForm(&form, client: client)
        return try await post(form: form, url: tokenURL, client: client)
    }

    public func revoke(
        token: String,
        tokenTypeHint: String,
        style: RevocationStyle,
        client: ClientCredentials
    ) async throws {
        switch style {
        case .rfc7009(let url, _):
            var form: [(String, String)] = [
                ("token", token),
                ("token_type_hint", tokenTypeHint),
            ]
            appendClientSecretToForm(&form, client: client)
            let (data, response) = try await execute(buildRequest(url: url, form: form, client: client))
            try checkStatus(response, data: data)
        case .dropboxAPI(let url):
            // Dropbox: POST body rỗng, Bearer access token.
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await execute(request)
            try checkStatus(response, data: data)
        case .unsupported:
            throw OAuthError.revocationUnsupported
        }
    }

    // MARK: - Nội bộ

    private struct ErrorBody: Decodable {
        let error: String
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private func appendClientSecretToForm(_ form: inout [(String, String)], client: ClientCredentials) {
        guard case .clientSecretPost = client.method, let secret = client.clientSecret else { return }
        form.append(("client_secret", secret))
    }

    /// RFC 6749 §2.3.1: form-encode id và secret RIÊNG, ghép bằng ":", rồi base64.
    private func basicAuthHeader(_ client: ClientCredentials) -> String? {
        guard case .clientSecretBasic = client.method, let secret = client.clientSecret else {
            return nil
        }
        let encoded = FormEncoding.escape(client.clientId) + ":" + FormEncoding.escape(secret)
        return "Basic \(Data(encoded.utf8).base64EncodedString())"
    }

    private func buildRequest(
        url: URL, form: [(String, String)], client: ClientCredentials?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(FormEncoding.encode(form).utf8)
        if let client, let header = basicAuthHeader(client) {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func post(
        form: [(String, String)], url: URL, client: ClientCredentials
    ) async throws -> TokenResponse {
        let (data, response) = try await execute(buildRequest(url: url, form: form, client: client))
        let status = response.statusCode
        guard (200...299).contains(status) else {
            // Body lỗi là JSON tùy chọn — không decode được vẫn báo lỗi HTTP thô.
            throw Self.mapProviderError(
                status: status,
                // try?: body lỗi JSON tùy chọn — hỏng vẫn báo lỗi HTTP thô.
                body: try? JSONDecoder().decode(ErrorBody.self, from: data))
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            // Thiếu access_token hoặc JSON hỏng → không dùng được.
            throw OAuthError.malformedResponse("token response: \(error.localizedDescription)")
        }
    }

    private func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await http.send(request)
        } catch let error as URLError {
            throw OAuthError.network(error.code)
        }
    }

    private func checkStatus(_ response: HTTPURLResponse, data: Data) throws {
        let status = response.statusCode
        guard !(200...299).contains(status) else { return }
        if status == 501 {
            // RFC 7009 §5: server không hỗ trợ revocation.
            throw OAuthError.revocationUnsupported
        }
        // Body lỗi là JSON tùy chọn — không decode được vẫn báo lỗi HTTP thô.
        throw Self.mapProviderError(
            status: status,
            // try?: body lỗi JSON tùy chọn — hỏng vẫn báo lỗi HTTP thô.
            body: try? JSONDecoder().decode(ErrorBody.self, from: data))
    }

    private static func mapProviderError(status: Int, body: ErrorBody?) -> OAuthError {
        // Đọc error JSON cho cả 401 — Google/Microsoft trả 400/401 tùy lúc.
        guard (400...499).contains(status) else {
            if (500...599).contains(status) { return .server(status: status) }
            return .malformedResponse("HTTP \(status)")
        }
        guard let body else { return .malformedResponse("HTTP \(status)") }
        switch body.error {
        case "invalid_grant": return .invalidGrant(body.errorDescription)
        case "invalid_client": return .invalidClient(body.errorDescription)
        case "invalid_scope": return .invalidScope(body.errorDescription)
        case "insufficient_scope": return .insufficientScope(body.errorDescription)
        case "access_denied": return .accessDenied(body.errorDescription)
        default: return .other(code: body.error, description: body.errorDescription)
        }
    }
}
