import Foundation
import KeyloftTestSupport
import Providers
import Testing
import VaultDomain

@Suite("OIDC Discovery")
struct DiscoveryTests {
    static func fixture(_ name: String) throws -> DiscoveryDocument {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DiscoveryDocument.self, from: data)
    }

    @Test("U5: decode 3 fixture discovery")
    func decodeFixtures() throws {
        let google = try Self.fixture("google-discovery")
        #expect(google.issuer == "https://accounts.google.com")
        #expect(google.authorizationEndpoint.absoluteString == "https://accounts.google.com/o/oauth2/v2/auth")
        #expect(google.tokenEndpoint.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(google.revocationEndpoint?.absoluteString == "https://oauth2.googleapis.com/revoke")
        #expect(google.authorizationResponseIssParameterSupported == true)
        #expect(google.codeChallengeMethodsSupported?.contains("S256") == true)

        let microsoft = try Self.fixture("microsoft-discovery")
        #expect(microsoft.issuer == "https://login.microsoftonline.com/{tenantid}/v2.0")
        #expect(microsoft.revocationEndpoint == nil)

        let dropbox = try Self.fixture("dropbox-discovery")
        #expect(dropbox.issuer == "https://www.dropbox.com")
        #expect(dropbox.tokenEndpoint.absoluteString == "https://api.dropboxapi.com/oauth2/token")
    }

    @Test("U6: merge cùng issuer — endpoint lấy từ doc, quirks khác giữ nguyên")
    func mergeSameIssuer() {
        let provider = TestData.googleProvider
        let doc = DiscoveryDocument(
            issuer: provider.issuer,
            authorizationEndpoint: URL(string: "https://example.test/google/auth2")!,
            tokenEndpoint: URL(string: "https://example.test/google/token2")!,
            revocationEndpoint: URL(string: "https://example.test/google/revoke2")!,
            authorizationResponseIssParameterSupported: true)
        let merged = OIDCDiscovery.merge(provider, doc)

        #expect(merged.authURL.absoluteString == "https://example.test/google/auth2")
        #expect(merged.tokenURL.absoluteString == "https://example.test/google/token2")
        #expect(merged.revokeURL?.absoluteString == "https://example.test/google/revoke2")
        #expect(merged.quirks.authorizationResponseIssSupported == true)
        #expect(merged.quirks.rotatesRefreshToken == provider.quirks.rotatesRefreshToken)
        #expect(merged.quirks.scopeAliases == provider.quirks.scopeAliases)
        #expect(merged.defaultScopes == provider.defaultScopes)
    }

    @Test("U7: merge issuer lạ → trả provider tĩnh y nguyên")
    func mergeWrongIssuer() {
        let doc = DiscoveryDocument(
            issuer: "https://evil.example",
            authorizationEndpoint: URL(string: "https://evil/auth")!,
            tokenEndpoint: URL(string: "https://evil/token")!)
        #expect(OIDCDiscovery.merge(TestData.googleProvider, doc) == TestData.googleProvider)
    }

    @Test("U8: doc không S256 → bỏ doc")
    func mergeNoS256() {
        let provider = TestData.microsoftProvider
        let doc = DiscoveryDocument(
            issuer: provider.issuer,
            authorizationEndpoint: URL(string: "https://example.test/ms2/auth")!,
            tokenEndpoint: URL(string: "https://example.test/ms2/token")!,
            codeChallengeMethodsSupported: ["plain"])
        #expect(OIDCDiscovery.merge(provider, doc) == provider)
    }

    @Test("U9: discovery lỗi mạng → refreshDiscovery không throw, provider() trả tĩnh")
    func refreshSwallowsErrors() async throws {
        let stub = StubHTTPClient()
        // Không đăng ký route nào → mọi request throw URLError → ProviderError.discovery.
        let catalog = ProviderCatalog(discovery: OIDCDiscovery(http: stub))
        await catalog.refreshDiscovery()

        let google = try await catalog.provider(.google)
        #expect(google == Provider.google)
        #expect(stub.requests.count == 3)
    }

    @Test("Catalog áp discovery đã merge qua provider()")
    func catalogAppliesDiscovery() async throws {
        let stub = StubHTTPClient()
        let doc = DiscoveryDocument(
            issuer: Provider.google.issuer,
            authorizationEndpoint: Provider.google.authURL,
            tokenEndpoint: URL(string: "https://example.test/google/token-new")!,
            revocationEndpoint: Provider.google.revokeURL,
            authorizationResponseIssParameterSupported: true)
        let payload = try JSONEncoder().encode(doc)
        stub.on("GET", "https://accounts.google.com", json: String(decoding: payload, as: UTF8.self))
        // MS/Dropbox không có route → lỗi → giữ tĩnh.
        let catalog = ProviderCatalog(discovery: OIDCDiscovery(http: stub))
        await catalog.refreshDiscovery()

        let google = try await catalog.provider(.google)
        #expect(google.tokenURL.absoluteString == "https://example.test/google/token-new")
        #expect(google.quirks.authorizationResponseIssSupported == true)
        let microsoft = try await catalog.provider(.microsoft)
        #expect(microsoft == Provider.microsoft)
    }
}
