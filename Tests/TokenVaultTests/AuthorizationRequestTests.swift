import Foundation
import KeyloftTestSupport
import Testing
import TokenVault
import VaultDomain

@Suite("AuthorizationRequest")
struct AuthorizationRequestTests {
    static func makeRequest(
        provider: Provider = TestData.googleProvider,
        redirect: URL = URL(string: "http://127.0.0.1:5000/callback")!,
        includeGranted: Bool = false,
        loginHint: String? = nil
    ) throws -> AuthorizationRequest {
        AuthorizationRequest(
            provider: provider,
            clientId: "client-1.apps.googleusercontent.com",
            redirectURI: redirect,
            scopes: ["openid", "email", "drive"],
            state: "STATE-123",
            pkce: try PKCEPair(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            loginHint: loginHint,
            includeGrantedScopes: includeGranted)
    }

    @Test("U6: URL đủ tham số, thứ tự cố định (Google)")
    func fullURL() throws {
        let request = try Self.makeRequest()
        let url = try request.url()
        let expected =
            "https://example.test/google/auth"
            + "?response_type=code"
            + "&client_id=client-1.apps.googleusercontent.com"
            + "&redirect_uri=http%3A%2F%2F127.0.0.1%3A5000%2Fcallback"
            + "&scope=drive%20email%20openid"
            + "&state=STATE-123"
            + "&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
            + "&code_challenge_method=S256"
            + "&access_type=offline"
            + "&prompt=consent"
        #expect(url.absoluteString == expected)
    }

    @Test("U7: percent-encode RFC 3986 — space %20, giữ : / qua encode")
    func percentEncoding() throws {
        // scope chứa ký tự cần encode.
        let provider = TestData.googleProvider
        let request = AuthorizationRequest(
            provider: provider,
            clientId: "cid",
            redirectURI: URL(string: "http://127.0.0.1:5000/callback")!,
            scopes: ScopeSet(spaceDelimited: "https://www.googleapis.com/auth/drive openid"),
            state: "s",
            pkce: try PKCEPair(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
        let query =
            URLComponents(url: try request.url(), resolvingAgainstBaseURL: false)?
            .percentEncodedQuery ?? ""
        #expect(query.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A5000%2Fcallback"))
        #expect(
            query.contains(
                "scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive%20openid"))
        #expect(!query.contains("+"))
    }

    @Test("U8: include_granted_scopes bật/tắt")
    func includeGranted() throws {
        let on =
            URLComponents(
                url: try Self.makeRequest(includeGranted: true).url(), resolvingAgainstBaseURL: false
            )?.percentEncodedQuery ?? ""
        #expect(on.contains("include_granted_scopes=true"))
        let off =
            URLComponents(
                url: try Self.makeRequest().url(), resolvingAgainstBaseURL: false
            )?.percentEncodedQuery ?? ""
        #expect(!off.contains("include_granted_scopes"))
    }

    @Test("U9: extraAuthParams cố ghi đè tham số bảo mật → invariantViolated")
    func protectedOverride() throws {
        var provider = TestData.googleProvider
        provider.extraAuthParams["state"] = "evil"
        #expect(
            throws: DomainError.invariantViolated(
                "extraAuthParams không được chứa key bảo mật: state")
        ) {
            _ = try Self.makeRequest(provider: provider).url()
        }
    }
}
