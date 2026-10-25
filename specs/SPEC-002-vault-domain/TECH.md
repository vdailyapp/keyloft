# SPEC-002: VaultDomain — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

Cần bộ type ổn định trước khi song song hóa. Mọi thay đổi public API ở đây sau khi T03 merge phải
qua review GLM-5.3 vì ảnh hưởng mọi target.

## Relevant Code

- `Sources/VaultDomain/` (placeholder từ T01)
- `Tests/KeyloftTestSupport/` (placeholder từ T01)

## Current State

Chỉ có placeholder.

## Proposed Changes

### 1. File layout

```
Sources/VaultDomain/
├── Identifiers.swift        # EntityID protocol + các ID
├── Enums.swift              # ProviderID, AccountStatus, CredentialStatus, SecretKind, ...
├── ScopeSet.swift
├── Provider.swift           # Provider, ProviderQuirks, IncrementalAuthStyle, RevocationStyle
├── OAuthClient.swift
├── Account.swift
├── Credential.swift
├── Secret.swift             # Secret, KeychainRef
├── AccessToken.swift
├── HealthCheckResult.swift
├── AuditEvent.swift
├── Repositories.swift       # protocol repository
├── Infrastructure.swift     # DateProvider, IDGenerator, RandomSource, HTTPClient + impl hệ thống
└── DomainError.swift
```

### 2. Identifiers

```swift
public protocol EntityID: Hashable, Codable, Sendable, CustomStringConvertible {
    var rawValue: UUID { get }
    init(rawValue: UUID)
}
extension EntityID { public var description: String { rawValue.uuidString.lowercased() } }

public struct OAuthClientID: EntityID { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct AccountID: EntityID { ... }
public struct CredentialID: EntityID { ... }
public struct SecretID: EntityID { ... }
public struct HealthCheckID: EntityID { ... }
public struct AuditEventID: EntityID { ... }
```

Codable của ID encode thành chuỗi UUID đơn (`singleValueContainer`), không phải object.

### 3. Enums

```swift
public enum ProviderID: String, Codable, Sendable, CaseIterable { case google, microsoft, dropbox }

public enum AccountStatus: String, Codable, Sendable, CaseIterable {
    case healthy, degraded, needsConsent, needsReauth, unreachable
    /// Mức nghiêm trọng để chọn badge menu bar: needsReauth > needsConsent > unreachable > degraded > healthy
    public var severity: Int { ... }   // 4,3,2,1,0
}

public enum CredentialStatus: String, Codable, Sendable { case active, superseded, revoked }

public enum SecretKind: String, Codable, Sendable, CaseIterable { case apiKey, password, clientSecret, refreshToken }
```

### 4. ScopeSet

```swift
public struct ScopeSet: Hashable, Codable, Sendable, ExpressibleByArrayLiteral, CustomStringConvertible {
    public private(set) var values: Set<String>
    public init(_ values: some Sequence<String>)     // trim, bỏ rỗng
    public init(spaceDelimited: String)              // tách theo whitespace (RFC 6749 §3.3)
    public init(arrayLiteral: String...)
    public var spaceDelimited: String                // sorted, nối bằng " "
    public var isEmpty: Bool
    public func contains(_ scope: String) -> Bool
    public func union(_ other: ScopeSet) -> ScopeSet
    public func subtracting(_ other: ScopeSet) -> ScopeSet
    public func isSuperset(of other: ScopeSet) -> Bool
    /// Scope trong self (cần) mà `granted` không có.
    public func missing(in granted: ScopeSet) -> ScopeSet { subtracting(granted) }
}
```

Codable: encode thành mảng chuỗi đã sắp xếp (ổn định cho DB/JSON). So sánh phân biệt hoa/thường
(scope là case-sensitive theo RFC 6749).

### 5. Entities

```swift
public struct ProviderQuirks: Codable, Sendable, Equatable {
    public var rotatesRefreshToken: Bool          // Microsoft: true
    public var needsOfflineParam: Bool            // Google access_type=offline, Dropbox token_access_type=offline
    public var incrementalAuth: IncrementalAuthStyle
    public var revocation: RevocationStyle
    public var issuerIsTenantTemplated: Bool      // Microsoft: iss = https://login.microsoftonline.com/{tenantid}/v2.0
    public var tokenEndpointAuth: TokenEndpointAuthMethod // .clientSecretPost | .clientSecretBasic | .none
    public var authorizationResponseIssSupported: Bool    // RFC 9207: true → callback BẮT BUỘC có iss
    /// Provider trả scope dạng khác lúc xin. Google: "email" → "https://www.googleapis.com/auth/userinfo.email".
    public var scopeAliases: [String: String]             // short → canonical
    /// Scope không bao giờ được echo lại trong token response (Microsoft: offline_access).
    public var unechoedScopes: ScopeSet
    /// Gửi `scope` (= grantedScopes) khi refresh. Microsoft: true; Google/Dropbox: false.
    public var refreshIncludesScope: Bool
}
public enum IncrementalAuthStyle: String, Codable, Sendable { case includeGrantedScopes, reauthorize, consoleThenRelogin }
public enum RevocationStyle: Codable, Sendable, Equatable {
    case rfc7009(URL, revokesWholeGrant: Bool)    // Google: whole grant = true
    case dropboxAPI(URL)                          // POST /2/auth/token/revoke, Bearer access token
    case unsupported                              // Microsoft
}
public enum TokenEndpointAuthMethod: String, Codable, Sendable { case clientSecretPost, clientSecretBasic, none }

public struct Provider: Sendable, Equatable, Identifiable {
    public let id: ProviderID
    public let displayName: String
    public let issuer: String                     // dùng so iss (RFC 9207) và id_token.iss
    public let authURL: URL
    public let tokenURL: URL
    public let revokeURL: URL?
    public let discoveryURL: URL?
    public let defaultScopes: ScopeSet            // cũng là "scope đang cần" ở giai đoạn 1
    public let extraAuthParams: [String: String]  // vd Google ["access_type": "offline", "prompt": "consent"]
    public let quirks: ProviderQuirks
}

public struct OAuthClient: Codable, Sendable, Equatable, Identifiable {
    public let id: OAuthClientID
    public var providerId: ProviderID
    public var clientId: String
    public var clientSecretRef: SecretID?         // nil = public client (PKCE only)
    public var redirectURI: URL                   // http://127.0.0.1/callback (không port = cổng ngẫu nhiên) hoặc có port cố định
    public var secretExpiresAt: Date?
    public var label: String
    public var createdAt: Date
}

public struct Account: Codable, Sendable, Equatable, Identifiable {
    public let id: AccountID
    public var providerId: ProviderID
    public var oauthClientId: OAuthClientID
    public var externalId: String                 // id_token.sub
    public var email: String?
    public var displayName: String?
    public var status: AccountStatus
    public var statusChangedAt: Date
    public var createdAt: Date
}

public struct Credential: Codable, Sendable, Equatable, Identifiable {
    public let id: CredentialID
    public var accountId: AccountID
    public var refreshTokenRef: SecretID
    public var requestedScopes: ScopeSet
    public var grantedScopes: ScopeSet
    public var issuedAt: Date
    public var supersededBy: CredentialID?
    public var status: CredentialStatus
}

public struct KeychainRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public static let service = "app.vdaily.keyloft"
    public let account: String                    // "<kind>.<secret-uuid>", vd "refreshToken.6f1c..."
    public init(kind: SecretKind, id: SecretID)
}

public struct Secret: Codable, Sendable, Equatable, Identifiable {
    public let id: SecretID
    public var kind: SecretKind
    public var label: String
    public var keychainRef: KeychainRef
    public var requiresUserPresence: Bool
    public var createdAt: Date
    public var rotatedAt: Date?
}

public struct AccessToken: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let value: String
    public let scopes: ScopeSet
    public let expiresAt: Date
    public func isValid(at now: Date, minValidity: TimeInterval) -> Bool { expiresAt.timeIntervalSince(now) > minValidity }
    public var description: String { "AccessToken(<redacted>, expiresAt: \(expiresAt))" }
    public var debugDescription: String { description }
}   // KHÔNG Codable: chỉ sống trong RAM

public enum HealthLayer: String, Codable, Sendable, CaseIterable { case tokenPresent, refresh, apiCall, scopes, earlyWarning }

public struct HealthCheckItem: Codable, Sendable, Equatable {
    public var name: HealthLayer
    public var ok: Bool
    public var latencyMs: Int?
    public var error: String?                     // thông điệp đã làm sạch, không chứa token
    public var warnings: [String]                 // chỉ dùng ở earlyWarning: "quota>90%", "clientSecret<30d", "slow"
}

public struct HealthCheckResult: Codable, Sendable, Equatable, Identifiable {
    public let id: HealthCheckID
    public var accountId: AccountID
    public var checkedAt: Date
    public var status: AccountStatus
    public var checks: [HealthCheckItem]
}

public enum AuditActor: String, Codable, Sendable { case user, app, cli, scheduler }

public enum AuditAction: String, Codable, Sendable {
    case accountAdded = "account.added", accountRemoved = "account.removed"
    case accountStatusChanged = "account.status_changed"
    case credentialIssued = "credential.issued", credentialSuperseded = "credential.superseded"
    case credentialRevoked = "credential.revoked"
    case tokenRefreshed = "token.refreshed", tokenRefreshFailed = "token.refresh_failed"
    case tokenIssued = "token.issued"          // access token giao cho caller ngoài app (CLI)
    case scopeGranted = "scope.granted", scopeDenied = "scope.denied", scopeReduced = "scope.reduced"
    case secretCreated = "secret.created", secretRead = "secret.read"
    case secretRotated = "secret.rotated", secretDeleted = "secret.deleted"
    case oauthClientCreated = "oauth_client.created", oauthClientDeleted = "oauth_client.deleted"
}

public enum AuditResult: Codable, Sendable, Equatable { case success, failure(reason: String) }

public struct AuditEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: AuditEventID
    public var actor: AuditActor
    public var action: AuditAction
    public var target: String                     // "account:<id>", "credential:<id>", "secret:<id>"
    public var scopes: ScopeSet?
    public var result: AuditResult
    public var timestamp: Date
}
```

Mọi struct có `public init` memberwise đầy đủ (Swift không tự sinh init public).

### 6. Repositories.swift

Mọi method `async throws`. Protocol `Sendable`.

```swift
public protocol OAuthClientRepository: Sendable {
    func save(_ client: OAuthClient) async throws             // upsert theo id
    func get(_ id: OAuthClientID) async throws -> OAuthClient?
    func list(provider: ProviderID?) async throws -> [OAuthClient]
    func delete(_ id: OAuthClientID) async throws             // throw .hasDependents nếu còn Account
}

public protocol AccountRepository: Sendable {
    func save(_ account: Account) async throws
    func get(_ id: AccountID) async throws -> Account?
    func find(provider: ProviderID, oauthClient: OAuthClientID, externalId: String) async throws -> Account?
    func list() async throws -> [Account]                     // sắp theo createdAt
    func updateStatus(_ id: AccountID, to status: AccountStatus, at: Date) async throws
    func delete(_ id: AccountID) async throws                 // cascade credential + health results
}

public protocol CredentialRepository: Sendable {
    func insert(_ credential: Credential) async throws
    func get(_ id: CredentialID) async throws -> Credential?
    func active(for account: AccountID) async throws -> Credential?   // status == .active, issuedAt mới nhất
    func list(for account: AccountID) async throws -> [Credential]
    func markSuperseded(_ id: CredentialID, by newId: CredentialID) async throws
    func markRevoked(_ id: CredentialID) async throws
    func updateGrantedScopes(_ id: CredentialID, _ scopes: ScopeSet) async throws
}

public protocol SecretMetadataRepository: Sendable {
    func insert(_ secret: Secret) async throws
    func get(_ id: SecretID) async throws -> Secret?
    func list(kind: SecretKind?) async throws -> [Secret]
    func markRotated(_ id: SecretID, at: Date) async throws
    func delete(_ id: SecretID) async throws
}

public protocol HealthCheckRepository: Sendable {
    /// Ghi thêm và giữ tối đa `HealthCheckRetention.perAccount` (50) bản ghi mới nhất cho account.
    func append(_ result: HealthCheckResult) async throws
    func latest(for account: AccountID) async throws -> HealthCheckResult?
    func list(for account: AccountID, limit: Int) async throws -> [HealthCheckResult]   // mới nhất trước
}
public enum HealthCheckRetention { public static let perAccount = 50 }

public struct AuditQuery: Sendable, Equatable {
    public var target: String?; public var actions: Set<AuditAction>?; public var since: Date?; public var limit: Int = 200
}
public protocol AuditLog: Sendable {
    func append(_ event: AuditEvent) async throws             // chỉ ghi thêm, không có update/delete
    func query(_ query: AuditQuery) async throws -> [AuditEvent]   // mới nhất trước
}
```

### 6b. ProviderRegistry (trong Repositories.swift)

`TokenVault` không được import `Providers`, nên tra cứu provider đi qua protocol này;
`Providers.ProviderCatalog` implement (SPEC-007), test dùng `InMemoryProviderRegistry`.

```swift
public protocol ProviderRegistry: Sendable {
    func provider(_ id: ProviderID) async throws -> Provider   // không có → DomainError.notFound("provider:<id>")
}
```

### 7. Infrastructure.swift

```swift
public protocol DateProvider: Sendable { func now() -> Date }
public struct SystemDateProvider: DateProvider { public init() {}; public func now() -> Date { Date() } }

public protocol IDGenerator: Sendable { func make() -> UUID }
public struct SystemIDGenerator: IDGenerator { ... UUID() }

public protocol RandomSource: Sendable { func bytes(count: Int) throws -> Data }
public struct SystemRandomSource: RandomSource { ... SecRandomCopyBytes; throw DomainError.randomUnavailable }

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
public struct URLSessionHTTPClient: HTTPClient {
    public init(session: URLSession = .shared)   // ephemeral config khuyến nghị: không cache, không cookie
}
```

`SystemRandomSource` dùng `Security` (`SecRandomCopyBytes`) — `Security` là framework hệ thống,
được phép import trong `Infrastructure.swift` (ngoại lệ duy nhất với quy tắc "chỉ Foundation";
cập nhật `check-imports.sh` cho phép `import Security` ở đúng file này).

### 8. DomainError.swift

```swift
public enum DomainError: Error, Sendable, Equatable {
    case notFound(String)          // "account:<id>"
    case hasDependents(String)
    case randomUnavailable
    case invariantViolated(String)
}
```

### 9. KeyloftTestSupport (T03)

```
Tests/KeyloftTestSupport/
├── FixedDateProvider.swift      # final class, có advance(by:) — dùng Mutex (Synchronization) để Sendable
├── SequentialIDGenerator.swift  # UUID 00000000-0000-0000-0000-00000000000N tăng dần
├── SeededRandomSource.swift     # trả bytes tất định từ seed (xorshift), hoặc bytes cố định
├── StubHTTPClient.swift         # xem dưới
├── InMemoryRepositories.swift   # actor InMemoryAccountRepository, ... cho cả 6 protocol + InMemoryProviderRegistry
└── Fixtures.swift               # TestData.googleProvider, .oauthClient(), .account(), .credential()
```

```swift
public final class StubHTTPClient: HTTPClient {
    public struct Route: Sendable { method: String; urlPrefix: String; respond: @Sendable (URLRequest) throws -> (Int, [String: String], Data) }
    public init(routes: [Route] = [])
    public func on(_ method: String, _ urlPrefix: String, status: Int = 200, json: String) // tiện lợi
    public func onError(_ method: String, _ urlPrefix: String, _ error: URLError)
    public var requests: [URLRequest] { get }  // ghi lại để assert body/header
    // Không khớp route → throw URLError(.unsupportedURL) để test fail rõ ràng.
}
```

Dùng `Synchronization.Mutex` (macOS 15+?) — **không**: deployment target là macOS 14, `Mutex` cần
macOS 15. Dùng `actor` cho repository và `NSLock` + `@unchecked Sendable` cho class fake trong
TestSupport (ngoại lệ cho phép, chỉ trong `Tests/`).

## Implementation Steps

1. **T02** — mục 2–5 (`Identifiers`, `Enums`, `ScopeSet`, entity). Test U1–U11.
2. **T03** — mục 6–9 (protocol, infra, error, TestSupport). Test U12.

## Testing

See ./TESTING.md

## Risks and Rollback

- Đổi public API sau khi nhiều task dựa vào → mọi PR đổi `Sources/VaultDomain` sau T03 cần
  review GLM-5.3 và ghi chú trong `handoff/BOARD.md`.

## Open Questions

- `Provider` không `Codable` (tĩnh trong code). Nếu SPEC-007 cần cache discovery xuống DB thì thêm
  `DiscoveryDocument` riêng, không làm `Provider` Codable.
