import Foundation
import KeyloftTestSupport
import Providers
import Testing
import VaultDomain

@Suite("ProviderCatalog")
struct ProviderCatalogTests {
    @Test("U1: bảng giá trị tĩnh khớp TECH §2")
    func staticValues() {
        let g = Provider.google
        #expect(g.issuer == "https://accounts.google.com")
        #expect(g.authURL.absoluteString == "https://accounts.google.com/o/oauth2/v2/auth")
        #expect(g.tokenURL.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(g.revokeURL?.absoluteString == "https://oauth2.googleapis.com/revoke")
        #expect(
            g.discoveryURL?.absoluteString
                == "https://accounts.google.com/.well-known/openid-configuration")
        #expect(
            g.defaultScopes == ["openid", "email", "https://www.googleapis.com/auth/drive"])
        #expect(g.extraAuthParams["access_type"] == "offline")
        #expect(g.extraAuthParams["prompt"] == "consent")
        #expect(g.quirks.rotatesRefreshToken == false)
        #expect(g.quirks.needsOfflineParam == true)
        #expect(g.quirks.incrementalAuth == .includeGrantedScopes)
        #expect(g.quirks.revocation == .rfc7009(g.revokeURL!, revokesWholeGrant: true))
        #expect(g.quirks.issuerIsTenantTemplated == false)
        #expect(g.quirks.tokenEndpointAuth == .clientSecretPost)
        #expect(g.quirks.authorizationResponseIssSupported == false)
        #expect(g.quirks.scopeAliases["email"] == "https://www.googleapis.com/auth/userinfo.email")
        #expect(g.quirks.unechoedScopes.isEmpty)
        #expect(g.quirks.refreshIncludesScope == false)

        let m = Provider.microsoft
        #expect(m.issuer == "https://login.microsoftonline.com/{tenantid}/v2.0")
        #expect(
            m.authURL.absoluteString
                == "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")
        #expect(
            m.tokenURL.absoluteString == "https://login.microsoftonline.com/common/oauth2/v2.0/token")
        #expect(m.revokeURL == nil)
        #expect(m.quirks.rotatesRefreshToken == true)
        #expect(m.quirks.needsOfflineParam == false)
        #expect(m.quirks.revocation == .unsupported)
        #expect(m.quirks.issuerIsTenantTemplated == true)
        #expect(m.quirks.unechoedScopes == ["offline_access"])
        #expect(m.quirks.refreshIncludesScope == true)
        #expect(m.extraAuthParams == ["prompt": "select_account"])

        let d = Provider.dropbox
        #expect(d.issuer == "https://www.dropbox.com")
        #expect(d.authURL.absoluteString == "https://www.dropbox.com/oauth2/authorize")
        #expect(d.tokenURL.absoluteString == "https://api.dropboxapi.com/oauth2/token")
        #expect(d.revokeURL?.absoluteString == "https://api.dropboxapi.com/2/auth/token/revoke")
        #expect(d.defaultScopes == ["account_info.read", "files.metadata.read", "openid", "email"])
        #expect(d.extraAuthParams == ["token_access_type": "offline"])
        #expect(d.quirks.needsOfflineParam == true)
        #expect(
            d.quirks.revocation
                == .dropboxAPI(
                    URL(string: "https://api.dropboxapi.com/2/auth/token/revoke")!))
    }

    @Test("U2: extraAuthParams không chứa key tham số bảo mật")
    func noSecurityOverride() {
        let forbidden: Set<String> = [
            "state", "code_challenge", "redirect_uri", "client_id", "response_type", "scope",
        ]
        for provider in ProviderCatalog.builtIn {
            for key in provider.extraAuthParams.keys {
                #expect(!forbidden.contains(key), "\(provider.id) có key cấm: \(key)")
            }
        }
    }

    @Test("U3: catalog tra cứu; rỗng → notFound")
    func catalogLookup() async throws {
        let catalog = ProviderCatalog()
        let dropbox = try await catalog.provider(.dropbox)
        #expect(dropbox.id == .dropbox)

        let empty = ProviderCatalog(providers: [])
        await #expect(throws: DomainError.notFound("provider:dropbox")) {
            _ = try await empty.provider(.dropbox)
        }
    }

    @Test("U4: Microsoft có scope offline_access; Google/Dropbox dùng param offline")
    func offlineHandling() {
        #expect(Provider.microsoft.defaultScopes.contains("offline_access"))
        #expect(Provider.google.extraAuthParams["access_type"] == "offline")
        #expect(Provider.dropbox.extraAuthParams["token_access_type"] == "offline")
        #expect(!Provider.google.defaultScopes.contains("offline_access"))
        #expect(!Provider.dropbox.defaultScopes.contains("offline_access"))
    }
}
