# SPEC-007: Providers — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

`Providers` chỉ được phụ thuộc `VaultDomain`, nên probe dùng `HTTPClient` của `VaultDomain`, và
`HealthCheck` gọi probe qua protocol.

## Relevant Code

- `Sources/VaultDomain/Provider.swift` — `Provider`, `ProviderQuirks`, `RevocationStyle` (SPEC-002 §5)
- `Sources/VaultDomain/Repositories.swift` — `ProviderRegistry` (SPEC-002 §6b)
- `Sources/VaultDomain/Infrastructure.swift` — `HTTPClient`

## Current State

Placeholder `Sources/Providers/Providers.swift`.

## Proposed Changes

### 1. File layout

```
Sources/Providers/
├── ProviderCatalog.swift        # T17: actor ProviderCatalog: ProviderRegistry
├── Google.swift                 # T17: extension Provider { static let google }
├── Microsoft.swift              # T17
├── Dropbox.swift                # T17
├── OIDCDiscovery.swift          # T18
├── APIProbe.swift               # T19: protocol + ProbeResult + ProbeError
├── GoogleDriveProbe.swift       # T19
├── MicrosoftGraphProbe.swift    # T19
└── DropboxProbe.swift           # T19
Tests/ProvidersTests/Fixtures/
├── google-discovery.json, microsoft-discovery.json, dropbox-discovery.json
├── google-about.json, microsoft-drive.json, dropbox-space-usage.json
└── google-403-insufficient.json, microsoft-403.json, dropbox-401.json
```

### 2. Giá trị tĩnh (T17)

| Field | Google | Microsoft | Dropbox |
| --- | --- | --- | --- |
| issuer | `https://accounts.google.com` | `https://login.microsoftonline.com/{tenantid}/v2.0` | `https://www.dropbox.com` |
| authURL | `https://accounts.google.com/o/oauth2/v2/auth` | `https://login.microsoftonline.com/common/oauth2/v2.0/authorize` | `https://www.dropbox.com/oauth2/authorize` |
| tokenURL | `https://oauth2.googleapis.com/token` | `https://login.microsoftonline.com/common/oauth2/v2.0/token` | `https://api.dropboxapi.com/oauth2/token` |
| revokeURL | `https://oauth2.googleapis.com/revoke` | — | `https://api.dropboxapi.com/2/auth/token/revoke` |
| discoveryURL | `https://accounts.google.com/.well-known/openid-configuration` | `https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration` | `https://www.dropbox.com/.well-known/openid-configuration` |
| defaultScopes | `openid email https://www.googleapis.com/auth/drive` | `openid email profile offline_access User.Read Files.ReadWrite` | `account_info.read files.metadata.read openid email` |
| extraAuthParams | `access_type=offline`, `prompt=consent` | `prompt=select_account` | `token_access_type=offline` |
| rotatesRefreshToken | false | true | false |
| needsOfflineParam | true | false (dùng scope `offline_access`) | true |
| incrementalAuth | `.includeGrantedScopes` | `.reauthorize` | `.consoleThenRelogin` |
| revocation | `.rfc7009(revokeURL, revokesWholeGrant: true)` | `.unsupported` | `.dropboxAPI(revokeURL)` |
| issuerIsTenantTemplated | false | true | false |
| tokenEndpointAuth | `.clientSecretPost` | `.clientSecretPost` | `.clientSecretPost` |
| authorizationResponseIssSupported | false (cập nhật từ discovery) | false | false |
| scopeAliases | `email`→`https://www.googleapis.com/auth/userinfo.email`, `profile`→`https://www.googleapis.com/auth/userinfo.profile` | — | — |
| unechoedScopes | — | `offline_access` | — |
| refreshIncludesScope | false | true | false |

> **Assumption:** giá trị trên đúng tại 2026-10-25; T18 thêm fixture discovery tải về hôm làm task
> và test so khớp, sai thì sửa bảng này trong cùng PR.

```swift
public actor ProviderCatalog: ProviderRegistry {
    public static let builtIn: [Provider] = [.google, .microsoft, .dropbox]
    public init(providers: [Provider] = builtIn, discovery: OIDCDiscovery? = nil)
    public func provider(_ id: ProviderID) async throws -> Provider   // áp discovery đã cache nếu có
    public func refreshDiscovery() async                               // tải cho mọi provider, lỗi → giữ tĩnh
}
```

### 3. Discovery (T18)

```swift
public struct DiscoveryDocument: Sendable, Equatable, Decodable {
    public var issuer: String
    public var authorizationEndpoint: URL, tokenEndpoint: URL
    public var revocationEndpoint: URL?
    public var authorizationResponseIssParameterSupported: Bool?   // snake_case keys
    public var codeChallengeMethodsSupported: [String]?
}
public struct OIDCDiscovery: Sendable {
    public init(http: any HTTPClient)
    public func fetch(_ url: URL) async throws -> DiscoveryDocument   // ProviderError.discovery(String)
    /// Trộn: endpoint/issuer lấy từ doc; cờ iss từ doc (nil → giữ). Không đổi quirks khác.
    public static func merge(_ provider: Provider, _ doc: DiscoveryDocument) -> Provider
}
```

Quy tắc an toàn khi merge: `doc.issuer` phải bằng `provider.issuer` (so template nguyên chuỗi với
Microsoft) — khác → **bỏ doc**, giữ tĩnh (chống discovery giả mạo). Nếu
`codeChallengeMethodsSupported` có mặt mà không chứa `S256` → bỏ doc và log.

### 4. Probe (T19)

```swift
public struct Quota: Sendable, Equatable { public var used: Int64; public var total: Int64? }
public struct ProbeResult: Sendable, Equatable {
    public var email: String?; public var quota: Quota?; public var latencyMs: Int
}
public enum ProbeError: Error, Sendable, Equatable {
    case unauthorized                 // 401
    case insufficientScope(String?)   // 403 + dấu hiệu scope
    case forbidden(String?)           // 403 khác
    case rateLimited                  // 429
    case server(Int)                  // 5xx
    case network(URLError.Code)
    case malformed(String)
    public var isTransient: Bool      // rateLimited, server, network
}
public protocol APIProbe: Sendable {
    func probe(accessToken: String) async throws -> ProbeResult
}
public enum ProbeFactory {
    public static func probe(for provider: ProviderID, http: any HTTPClient, clock: any DateProvider) -> any APIProbe
}
```

Parse:

- Google `about`: `user.emailAddress`, `storageQuota.usage` (string số), `storageQuota.limit`
  (string, có thể thiếu → `total = nil`). 403 body `error.errors[].reason == "insufficientPermissions"`
  hoặc header `WWW-Authenticate` chứa `insufficient_scope` → `.insufficientScope`.
- Microsoft `me/drive`: `owner.user.email`? (không đảm bảo) → `email = nil` được; `quota.used`,
  `quota.total` (Int64). 403 `error.code == "accessDenied"` + `WWW-Authenticate insufficient_scope`
  → `.insufficientScope`.
- Dropbox `get_space_usage`: RPC không tham số → gửi POST không body và **không** set
  Content-Type (Dropbox từ chối `application/json` với body rỗng). `used`,
  `allocation.allocated` (`.tag` = `individual`) hoặc `allocation.allocated` của team.
  401 `error.tag == "missing_scope"` → `.insufficientScope(required_scope)`; 401 khác → `.unauthorized`.
- `latencyMs` = thời gian `http.send` theo `clock` (FixedDateProvider trong test).
- Mọi request có `Authorization: Bearer <token>`; không log URL kèm token.

## Implementation Steps

1. **T17 (Flash)** — §2 + `ProviderCatalog` (chưa có discovery). U1–U4.
2. **T18 (Flash)** — §3 + nối vào `ProviderCatalog.refreshDiscovery`. U5–U9.
3. **T19 (Flash)** — §4. U10–U19.

T18 và T19 song song sau T17.

## Testing

See ./TESTING.md.

## Risks and Rollback

- Provider đổi endpoint → discovery cứu được auth/token; probe URL thì không — cần release.

## Open Questions

- Microsoft `prompt=select_account` có cản re-auth im lặng? Chủ ý: luôn cho chọn account.
