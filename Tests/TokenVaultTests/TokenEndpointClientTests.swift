import Foundation
import KeyloftTestSupport
import Testing
import TokenVault
import VaultDomain

@Suite("TokenEndpoint")
struct TokenEndpointClientTests {
    static let tokenURL = URL(string: "https://example.test/token")!
    static let revokeURL = URL(string: "https://example.test/revoke")!

    static func body(of request: URLRequest) -> String {
        String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    }

    @Test("U17: body exchange đúng trường, Content-Type form")
    func exchangeBody() async throws {
        let stub = StubHTTPClient()
        stub.on("POST", "https://example.test/token", json: #"{"access_token":"at","token_type":"Bearer"}"#)
        let client = TokenEndpointClient(http: stub)

        _ = try await client.exchangeCode(
            "CODE-1", verifier: "VER-1",
            redirectURI: URL(string: "http://127.0.0.1:5000/callback")!,
            tokenURL: Self.tokenURL,
            client: ClientCredentials(clientId: "cid", clientSecret: "cs", method: .clientSecretPost))

        let request = stub.requests[0]
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        let body = Self.body(of: request)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=CODE-1"))
        #expect(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A5000%2Fcallback"))
        #expect(body.contains("code_verifier=VER-1"))
        #expect(body.contains("client_id=cid"))
        #expect(body.contains("client_secret=cs"))
    }

    @Test("U18: client_secret_post vs basic")
    func authMethods() async throws {
        let stub = StubHTTPClient()
        stub.on("POST", "https://example.test/token", json: #"{"access_token":"at","token_type":"Bearer"}"#)
        let client = TokenEndpointClient(http: stub)

        _ = try await client.refresh(
            "rt", tokenURL: Self.tokenURL,
            client: ClientCredentials(clientId: "cid", clientSecret: "sec", method: .clientSecretPost))
        let post = stub.requests[0]
        #expect(Self.body(of: post).contains("client_secret=sec"))
        #expect(post.value(forHTTPHeaderField: "Authorization") == nil)

        _ = try await client.refresh(
            "rt", tokenURL: Self.tokenURL,
            client: ClientCredentials(clientId: "ci:d", clientSecret: "se:c", method: .clientSecretBasic))
        let basic = stub.requests[1]
        #expect(!Self.body(of: basic).contains("client_secret"))
        let expected = Data("ci%3Ad:se%3Ac".utf8).base64EncodedString()
        #expect(basic.value(forHTTPHeaderField: "Authorization") == "Basic \(expected)")
    }

    @Test("U19: refresh body + scope")
    func refreshBody() async throws {
        let stub = StubHTTPClient()
        stub.on("POST", "https://example.test/token", json: #"{"access_token":"at","token_type":"Bearer"}"#)
        let client = TokenEndpointClient(http: stub)

        _ = try await client.refresh(
            "rt-9", tokenURL: Self.tokenURL,
            client: ClientCredentials(clientId: "cid", clientSecret: nil, method: .none),
            scopes: ["a", "b"])
        let body = Self.body(of: stub.requests[0])
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=rt-9"))
        #expect(body.contains("scope=a+b"))
    }

    @Test("U20: invalid_grant kèm description")
    func invalidGrant() async throws {
        let stub = StubHTTPClient()
        stub.on(
            "POST", "https://example.test/token", status: 400,
            json: #"{"error":"invalid_grant","error_description":"revoked"}"#)
        let client = TokenEndpointClient(http: stub)
        await #expect(throws: OAuthError.invalidGrant("revoked")) {
            _ = try await client.refresh(
                "rt", tokenURL: Self.tokenURL,
                client: ClientCredentials(clientId: "c", clientSecret: nil, method: .none))
        }
    }

    @Test("U21: invalid_client / invalid_scope / mã lạ")
    func providerErrors() async throws {
        let stub = StubHTTPClient()
        let client = TokenEndpointClient(http: stub)
        let creds = ClientCredentials(clientId: "c", clientSecret: nil, method: .none)

        stub.on(
            "POST", "https://example.test/e1", status: 401,
            json: #"{"error":"invalid_client"}"#)
        await #expect(throws: OAuthError.invalidClient(nil)) {
            _ = try await client.refresh("rt", tokenURL: URL(string: "https://example.test/e1")!, client: creds)
        }

        stub.on(
            "POST", "https://example.test/e2", status: 400,
            json: #"{"error":"invalid_scope","error_description":"nope"}"#)
        await #expect(throws: OAuthError.invalidScope("nope")) {
            _ = try await client.refresh("rt", tokenURL: URL(string: "https://example.test/e2")!, client: creds)
        }

        stub.on(
            "POST", "https://example.test/e3", status: 400,
            json: #"{"error":"weird_error"}"#)
        await #expect(throws: OAuthError.other(code: "weird_error", description: nil)) {
            _ = try await client.refresh("rt", tokenURL: URL(string: "https://example.test/e3")!, client: creds)
        }
    }

    @Test("U22: 5xx → .server, isTransient")
    func serverError() async throws {
        let stub = StubHTTPClient()
        stub.on("POST", "https://example.test/token", status: 503, json: "service unavailable")
        let client = TokenEndpointClient(http: stub)
        do {
            _ = try await client.refresh(
                "rt", tokenURL: Self.tokenURL,
                client: ClientCredentials(clientId: "c", clientSecret: nil, method: .none))
            Issue.record("phải throw .server")
        } catch let error as OAuthError {
            #expect(error == .server(status: 503))
            #expect(error.isTransient)
        }
    }

    @Test("U23: lỗi mạng → .network, isTransient")
    func networkError() async throws {
        let stub = StubHTTPClient()
        stub.onError("POST", "https://example.test/token", URLError(.notConnectedToInternet))
        let client = TokenEndpointClient(http: stub)
        do {
            _ = try await client.refresh(
                "rt", tokenURL: Self.tokenURL,
                client: ClientCredentials(clientId: "c", clientSecret: nil, method: .none))
            Issue.record("phải throw .network")
        } catch let error as OAuthError {
            #expect(error == .network(.notConnectedToInternet))
            #expect(error.isTransient)
        }
    }

    @Test("U24: 4xx không JSON / 2xx thiếu access_token → malformedResponse")
    func malformed() async throws {
        let stub = StubHTTPClient()
        let client = TokenEndpointClient(http: stub)
        let creds = ClientCredentials(clientId: "c", clientSecret: nil, method: .none)

        stub.on(
            "POST", "https://example.test/html", status: 400, json: "<html>oops</html>",
            headers: ["Content-Type": "text/html"])
        await #expect(throws: OAuthError.malformedResponse("HTTP 400")) {
            _ = try await client.refresh("rt", tokenURL: URL(string: "https://example.test/html")!, client: creds)
        }

        stub.on("POST", "https://example.test/empty", status: 200, json: "{}")
        await #expect(throws: OAuthError.self) {
            _ = try await client.refresh(
                "rt", tokenURL: URL(string: "https://example.test/empty")!, client: creds)
        }
    }

    @Test("U25: revoke 3 kiểu")
    func revoke() async throws {
        let stub = StubHTTPClient()
        stub.on("POST", "https://example.test/revoke", json: "{}")
        stub.on("POST", "https://example.test/dbx", json: "{}")
        let client = TokenEndpointClient(http: stub)
        let creds = ClientCredentials(clientId: "cid", clientSecret: "sec", method: .clientSecretPost)

        try await client.revoke(
            token: "rt-1", tokenTypeHint: "refresh_token",
            style: .rfc7009(Self.revokeURL, revokesWholeGrant: true), client: creds)
        let rfc = Self.body(of: stub.requests[0])
        #expect(rfc.contains("token=rt-1"))
        #expect(rfc.contains("token_type_hint=refresh_token"))

        try await client.revoke(
            token: "at-1", tokenTypeHint: "access_token",
            style: .dropboxAPI(URL(string: "https://example.test/dbx")!), client: creds)
        let dbx = stub.requests[1]
        #expect(dbx.value(forHTTPHeaderField: "Authorization") == "Bearer at-1")

        await #expect(throws: OAuthError.revocationUnsupported) {
            try await client.revoke(
                token: "x", tokenTypeHint: "refresh_token", style: .unsupported, client: creds)
        }
    }

    @Test("U26: TokenResponse không lộ token trong description")
    func redacted() throws {
        let json = Data(
            #"{"access_token":"ACCESS-XYZ","token_type":"Bearer","refresh_token":"REFRESH-XYZ","id_token":"ID-XYZ"}"#
                .utf8)
        let response = try JSONDecoder().decode(TokenResponse.self, from: json)
        let text = String(describing: response)
        #expect(!text.contains("ACCESS-XYZ"))
        #expect(!text.contains("REFRESH-XYZ"))
        #expect(!text.contains("ID-XYZ"))
        #expect(text.contains("<redacted>"))
    }
}
