# SPEC-005: Đăng nhập OAuth — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

Luồng có 3 phần bất đồng bộ chạy đua nhau (trình duyệt, server loopback, timeout) và một chuỗi
ghi không có transaction chung (Keychain + SQLite). Mỗi phần phải tách được để test riêng, và
phần điều phối phải có điểm bồi hoàn rõ ràng khi lỗi giữa chừng.

## Relevant Code

- `Sources/VaultDomain/Provider.swift` — `Provider`, `ProviderQuirks` (SPEC-002 §5)
- `Sources/VaultDomain/Repositories.swift` — repo + `ProviderRegistry` (SPEC-002 §6, §6b)
- `Sources/VaultDomain/Infrastructure.swift` — `HTTPClient`, `RandomSource`, `DateProvider`, `IDGenerator`
- `Sources/SecretVault/SecretVault.swift` — `SecretVault.create/read/delete` (SPEC-004 §3)

## Current State

Placeholder `Sources/TokenVault/TokenVault.swift`.

## Proposed Changes

### 1. File layout

```
Sources/TokenVault/
├── Base64URL.swift                 # T10
├── PKCE.swift                      # T10: PKCEPair, OAuthState, constantTimeEquals
├── AuthorizationRequest.swift      # T11
├── ScopeNormalizer.swift           # T11
├── Loopback/
│   ├── CallbackReceiver.swift      # T12: protocol + CallbackParameters
│   ├── LoopbackServer.swift        # T12: NWListener impl
│   └── HTTPRequestParser.swift     # T12: parse request line, query
├── BrowserSession.swift            # T12: protocol (impl ASWebAuthenticationSession ở App, SPEC-011)
├── OAuthError.swift                # T13
├── TokenEndpointClient.swift       # T13: exchange, refresh, revoke
├── FormEncoding.swift              # T13
├── IDToken.swift                   # T14
└── OAuthLoginService.swift         # T15
Tests/KeyloftTestSupport/
├── FakeBrowserSession.swift        # T12
└── FakeCallbackReceiver.swift      # T12
```

### 2. PKCE & state (T10) — RFC 7636

```swift
public enum Base64URL {
    public static func encode(_ data: Data) -> String      // không padding, +→-, /→_
    public static func decode(_ string: String) -> Data?   // tự thêm padding
}
public struct PKCEPair: Sendable, Equatable {
    public let verifier: String        // 43–128 ký tự unreserved
    public let challenge: String       // BASE64URL(SHA256(ASCII(verifier)))
    public let method = "S256"
    public static func generate(using random: any RandomSource) throws -> PKCEPair   // 32 byte → 43 ký tự
    public init(verifier: String) throws     // validate độ dài/ký tự, tính challenge (để test vector RFC)
}
public enum OAuthState {
    public static func generate(using random: any RandomSource) throws -> String     // 32 byte base64url
}
public func constantTimeEquals(_ a: String, _ b: String) -> Bool
```

SHA256 bằng `CryptoKit` (`import CryptoKit` được phép trong TokenVault).

### 3. AuthorizationRequest (T11)

```swift
public struct AuthorizationRequest: Sendable {
    public var provider: Provider
    public var clientId: String
    public var redirectURI: URL
    public var scopes: ScopeSet
    public var state: String
    public var pkce: PKCEPair
    public var loginHint: String?
    public var includeGrantedScopes: Bool = false    // Google incremental
    public func url() throws -> URL                   // lỗi cấu hình → DomainError.invariantViolated
}
```

Query params (thứ tự cố định để test so chuỗi): `response_type=code`, `client_id`, `redirect_uri`,
`scope` (`scopes.spaceDelimited`), `state`, `code_challenge`, `code_challenge_method=S256`, rồi
`provider.extraAuthParams` sắp theo key, rồi `include_granted_scopes=true` nếu bật, `login_hint`
nếu có. Percent-encode theo RFC 3986 (space → `%20`, không dùng `+`). Không được ghi đè
tham số bảo mật bằng `extraAuthParams` (key trùng → `invariantViolated`).

```swift
public enum ScopeNormalizer {
    /// Canonical hóa theo `quirks.scopeAliases`, rồi cộng `requested ∩ unechoedScopes`.
    /// `responseScope == nil` → RFC 6749 §5.1: coi như cấp đủ `requested`.
    public static func granted(responseScope: String?, requested: ScopeSet, provider: Provider) -> ScopeSet
    public static func canonical(_ scopes: ScopeSet, provider: Provider) -> ScopeSet
}
```

`denied = canonical(requested).missing(in: granted)`.

### 4. Loopback & browser (T12) — RFC 8252 §7.3

```swift
public struct CallbackParameters: Sendable, Equatable {
    public var code: String?, state: String?, iss: String?, error: String?, errorDescription: String?
}
public protocol CallbackReceiver: Sendable {
    func start() async throws -> URL                       // redirect URI thật (có port)
    func waitForCallback() async throws -> CallbackParameters
    func stop() async
}
public typealias CallbackReceiverFactory = @Sendable (_ configuredRedirect: URL) -> any CallbackReceiver

public actor LoopbackServer: CallbackReceiver {
    public static let completionURL = URL(string: "app.vdaily.keyloft://oauth-complete")!
    public init(configuredRedirect: URL, timeout: Duration = .seconds(300))
}
public enum LoopbackError: Error, Sendable, Equatable { case bindFailed(String), timeout, cancelled, invalidRedirect }

public enum BrowserSessionError: Error, Sendable, Equatable { case userCancelled, failed(String) }
public protocol BrowserSession: Sendable {
    /// Mở URL; trả về khi trình duyệt tới `callbackScheme://...`; throw `BrowserSessionError.userCancelled` nếu người dùng đóng.
    func present(_ url: URL, callbackScheme: String) async throws
}
```

`LoopbackServer`:

- `configuredRedirect` phải có host `127.0.0.1`, scheme `http`; path mặc định `/callback`.
  Port trong URL = 0 hoặc không có → cổng ngẫu nhiên; có port → bind đúng port đó (Dropbox cần
  redirect cố định — xem SPEC-007).
- `NWListener` với `NWParameters.tcp`, `requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: …)`.
  NWListener cần `DispatchQueue` — **được phép** ở file này (một serial queue private, comment lý do);
  bắc cầu sang actor bằng `CheckedContinuation`.
- Mỗi connection: đọc tối đa 8 KB tới `\r\n\r\n`. Không phải `GET` → 405. Path khác → 404 (vẫn chờ,
  vd `/favicon.ico`). Đúng path → parse query thành `CallbackParameters`, trả
  `302 Location: app.vdaily.keyloft://oauth-complete` + body HTML ngắn (fallback nếu trình duyệt
  không theo scheme), resume continuation, rồi `stop()`.
- Chỉ callback hợp lệ **đầu tiên** được nhận; sau đó listener đóng.
- Timeout → `LoopbackError.timeout`; `stop()` khi đang chờ → `.cancelled`.

`FakeBrowserSession` (TestSupport): cấu hình hành vi: `.redirect(code:, state: .echo|.fixed(String), iss:)`
— đọc `redirect_uri` + `state` từ URL được mở rồi **gửi HTTP GET thật** tới loopback; `.cancel`;
`.error(param)`. Ghi lại `openedURLs`.

`FakeCallbackReceiver`: trả `CallbackParameters` dựng sẵn, URL `http://127.0.0.1:55555/callback`.

### 5. Token endpoint (T13) — RFC 6749 §4.1.3, §6; RFC 7009

```swift
public struct TokenResponse: Sendable, Equatable, Decodable {
    public var accessToken: String, tokenType: String, expiresIn: Int?
    public var refreshToken: String?, scope: String?, idToken: String?
}   // CodingKeys snake_case; description che token

public struct ClientCredentials: Sendable {
    public var clientId: String; public var clientSecret: String?; public var method: TokenEndpointAuthMethod
}

public struct TokenEndpointClient: Sendable {
    public init(http: any HTTPClient)
    public func exchangeCode(_ code: String, verifier: String, redirectURI: URL,
                             tokenURL: URL, client: ClientCredentials) async throws -> TokenResponse
    public func refresh(_ refreshToken: String, tokenURL: URL, client: ClientCredentials,
                        scopes: ScopeSet?) async throws -> TokenResponse
    public func revoke(token: String, tokenTypeHint: String, style: RevocationStyle,
                       client: ClientCredentials) async throws
}

public enum OAuthError: Error, Sendable, Equatable {
    // từ provider
    case invalidGrant(String?), invalidClient(String?), invalidScope(String?)
    case insufficientScope(String?), accessDenied(String?), other(code: String, description: String?)
    // luồng
    case userCancelled, timeout, stateMismatch, issuerMismatch(expected: String, actual: String?)
    case accountMismatch(expectedExternalId: String, actualEmail: String?)
    case missingRefreshToken, missingIDToken, invalidIDToken(String), missingCode
    // hạ tầng
    case network(URLError.Code), server(status: Int), malformedResponse(String)
    case revocationUnsupported

    /// true → lỗi tạm thời, KHÔNG được chuyển account sang needsReauth.
    public var isTransient: Bool { network, server }
}
```

Request: `POST`, `Content-Type: application/x-www-form-urlencoded`, `Accept: application/json`.
Body form-encode (`FormEncoding.encode([(String,String)])`, space → `+`, theo WHATWG
`application/x-www-form-urlencoded`).

- exchange: `grant_type=authorization_code`, `code`, `redirect_uri`, `code_verifier`, `client_id`
  (+ `client_secret` nếu `.clientSecretPost`).
- refresh: `grant_type=refresh_token`, `refresh_token`, `client_id`, `scope` nếu truyền.
- `.clientSecretBasic`: header `Authorization: Basic base64(formEncode(id):formEncode(secret))`
  (RFC 6749 §2.3.1), không gửi `client_secret` trong body.
- Map response: 2xx → decode (`expiresIn` thiếu → 3600 khi dựng AccessToken ở SPEC-006); thiếu
  `access_token` → `malformedResponse`. 4xx có JSON `error` → map `invalid_grant`,
  `invalid_client`, `invalid_scope`, `access_denied`, khác → `.other`. 4xx không JSON →
  `malformedResponse("HTTP <code>")`. 5xx → `.server`. `URLError` → `.network(code)`.
- `revoke`: `.rfc7009(url, _)` → POST `token`, `token_type_hint`, client auth;
  `.dropboxAPI(url)` → POST với `Authorization: Bearer <token>` (token phải là access token), body rỗng;
  `.unsupported` → throw `.revocationUnsupported`. 200 → ok (RFC 7009: token lạ cũng 200).

### 6. ID token (T14) — OIDC Core §3.1.3.7

```swift
public struct IDTokenClaims: Sendable, Equatable, Decodable {
    public var iss: String, sub: String, aud: [String]      // aud chấp nhận string hoặc array
    public var exp: Date, iat: Date?                          // NumericDate (giây)
    public var email: String?, emailVerified: Bool?, name: String?
    public var preferredUsername: String?, tid: String?       // Microsoft
    public static func decode(_ jwt: String) throws -> IDTokenClaims   // OAuthError.invalidIDToken
    public func validate(provider: Provider, clientId: String, now: Date, leeway: TimeInterval = 300) throws
    public var bestEmail: String? { email ?? preferredUsername }
}
```

Validate: `aud` chứa `clientId`; `exp + leeway > now`; `iss`:
`quirks.issuerIsTenantTemplated` → `iss == provider.issuer.replacingOccurrences(of: "{tenantid}", with: tid)`
và `tid` khác nil; ngược lại `iss == provider.issuer`. Không verify chữ ký (PRODUCT Open Questions).
JWT phải có đúng 3 phần; `alg` = `none` → từ chối.

### 7. OAuthLoginService (T15)

```swift
public enum LoginTarget: Sendable, Equatable { case newAccount, existing(AccountID) }

public struct LoginRequest: Sendable, Equatable {
    public var oauthClientId: OAuthClientID
    public var scopes: ScopeSet                 // service gọi (SPEC-009/UI) quyết định; thường provider.defaultScopes
    public var target: LoginTarget
    public var includeGrantedScopes: Bool = false
    public var loginHint: String?
}
public struct LoginOutcome: Sendable, Equatable {
    public var account: Account, credential: Credential
    public var deniedScopes: ScopeSet, isNewAccount: Bool
}

public typealias CredentialIssuedObserver = @Sendable (AccountID, AccessToken) async -> Void

public actor OAuthLoginService {
    public init(providers: any ProviderRegistry, clients: any OAuthClientRepository,
                accounts: any AccountRepository, credentials: any CredentialRepository,
                secrets: SecretVault, audit: any AuditLog, tokenEndpoint: TokenEndpointClient,
                browser: any BrowserSession, receivers: @escaping CallbackReceiverFactory,
                random: any RandomSource, clock: any DateProvider, ids: any IDGenerator,
                onCredentialIssued: CredentialIssuedObserver? = nil)
    public func login(_ request: LoginRequest) async throws -> LoginOutcome
}
```

Luồng `login` (mỗi bước ghi chú lỗi throw):

1. `client = clients.get` (nil → `DomainError.notFound`), `provider = providers.provider(client.providerId)`.
2. `pkce`, `state`. `receiver = receivers(client.redirectURI)`; `redirect = receiver.start()`.
   `defer { await receiver.stop() }` (dùng `do/catch` + stop vì `defer` không await được).
3. `clientSecret = client.clientSecretRef.map { secrets.read($0, reason:…, actor: .app) }` → UTF-8.
4. URL từ `AuthorizationRequest`. Chạy đua bằng `withThrowingTaskGroup`:
   - task A: `browser.present(url, callbackScheme: "app.vdaily.keyloft")` — `BrowserSessionError.userCancelled` → `OAuthError.userCancelled`; trả về bình thường thì
     **không** kết thúc nhóm (tiếp tục chờ B); throw → hủy nhóm.
   - task B: `receiver.waitForCallback()` → kết quả nhóm. Có kết quả B → `group.cancelAll()`.
5. `params.error != nil` → `access_denied` → `.accessDenied(desc)`, khác → `.other`.
6. `constantTimeEquals(params.state ?? "", state)` sai → audit failure `credentialIssued`
   (`result: .failure("state mismatch")`) → `.stateMismatch`. **Không gọi token endpoint.**
7. RFC 9207: `iss` có → phải khớp issuer (cùng quy tắc template của §6 nhưng không có `tid` →
   so pattern `https://login.microsoftonline.com/<uuid>/v2.0`); `iss` thiếu mà
   `quirks.authorizationResponseIssSupported` → `.issuerMismatch(expected, nil)`.
8. `code` thiếu → `.missingCode`. `tokens = exchangeCode(...)` với `redirect` thật (exact match).
9. `refreshToken` thiếu → `.missingRefreshToken`. `idToken` thiếu → `.missingIDToken`.
   `claims = decode + validate`.
10. `granted = ScopeNormalizer.granted(...)`, `denied = canonical(request.scopes).missing(in: granted)`.
11. Account:
    - `.existing(id)`: `get(id)` (nil → notFound); `externalId != claims.sub` →
      `.accountMismatch(...)`. Cập nhật `email/displayName`.
    - `.newAccount`: `find(provider, client, sub)` → có thì dùng (isNewAccount = false), không thì tạo
      mới (`status` tính ở bước 13).
12. `secret = secrets.create(kind: .refreshToken, label: "<provider> <email>", value:, actor: .user)`.
    Từ đây lỗi → `secrets.delete(secret.id)` bồi hoàn rồi rethrow.
13. `status = denied.isEmpty ? .healthy : .needsConsent`; `accounts.save(account)`.
14. `previous = credentials.active(account.id)`; insert credential mới (active,
    `requestedScopes = canonical(request.scopes)`, `grantedScopes = granted`);
    `previous` → `markSuperseded(previous.id, by: new.id)` + audit `credentialSuperseded`.
    Secret của credential cũ **giữ nguyên** (SPEC-009 dọn).
15. Audit (actor `.user`, target `account:<id>`): `accountAdded` (nếu mới), `credentialIssued`
    (scopes = granted), `scopeGranted` (granted), `scopeDenied` (nếu denied ≠ ∅).
16. `onCredentialIssued?(account.id, AccessToken(value: tokens.accessToken, scopes: granted,
    expiresAt: now + (expiresIn ?? 3600)))`.

## Implementation Steps

1. **T10 (Flash)** — §2. U1–U5.
2. **T11 (Flash)** — §3. U6–U11.
3. **T12 (GLM-5.3)** — §4. U12–U16, I1.
4. **T13 (Flash)** — §5. U17–U26.
5. **T14 (Flash)** — §6 (dùng `Base64URL` của T10, `OAuthError` của T13). U27–U32.
6. **T15 (GLM-5.3)** — §7. U33–U45, I2.

T12 chạy ngay sau T02; T10, T13 sau T03; T11, T14 sau T10/T13 (xem `handoff/README.md` mục Wave).

## Testing

See ./TESTING.md. Seam bắt buộc: `CallbackReceiverFactory`, `BrowserSession`, `HTTPClient`,
`RandomSource` — `OAuthLoginService` không được tự tạo các đối tượng này.

## Risks and Rollback

- Một số trình duyệt chặn redirect sang custom scheme → trang HTML fallback vẫn báo thành công;
  `ASWebAuthenticationSession` phía app cần `cancel()` khi B xong trước (SPEC-011).
- Cổng ngẫu nhiên: Google "Desktop app" client và Microsoft "Mobile and desktop" chấp nhận mọi cổng
  loopback; Dropbox cần redirect khai báo chính xác → `OAuthClient.redirectURI` có port cố định.

## Open Questions

- Dọn secret của credential `superseded`: xóa ngay hay giữ để rollback? Leaning: SPEC-009 xóa
  ngay sau khi credential mới refresh thành công lần đầu.
