# SPEC-009: Quản lý scope, thu hồi, xóa account — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

Thứ tự thao tác quan trọng (Keychain không có transaction, FK `credential → secret` là RESTRICT),
và hành vi khác nhau theo provider phải đi qua `ProviderQuirks`, không `if provider ==`.

## Relevant Code

- `Sources/TokenVault/OAuthLoginService.swift` — `login(_:)`, `LoginRequest`, `LoginTarget` (SPEC-005 §7)
- `Sources/TokenVault/TokenProvider.swift` — `forceRefresh`, `invalidate` (SPEC-006)
- `Sources/TokenVault/TokenEndpointClient.swift` — `refresh`, `revoke` (SPEC-005 §5)
- `Sources/VaultDomain/Provider.swift` — `IncrementalAuthStyle`, `RevocationStyle`
- `Sources/VaultPersistence/Migrations.swift` — FK RESTRICT `credential.refresh_token_ref` (SPEC-003 §3)

## Current State

Sau SPEC-006: login tạo Credential mới và supersede cũ; secret cũ vẫn còn.

## Proposed Changes

### 1. File

```
Sources/TokenVault/ScopeService.swift
Sources/TokenVault/LoginRunner.swift       # protocol + extension OAuthLoginService: LoginRunner
Tests/KeyloftTestSupport/FakeLoginRunner.swift
```

### 2. Interface

```swift
public protocol LoginRunner: Sendable { func login(_ request: LoginRequest) async throws -> LoginOutcome }

public enum GrantMorePlan: Sendable, Equatable {
    case browser(LoginRequest)
    /// Dropbox: người dùng tick scope trong App Console trước, rồi chạy `then`.
    case consoleThenRelogin(consoleURL: URL, missing: ScopeSet, then: LoginRequest)
    case nothingMissing
}

public enum RevocationOutcome: Sendable, Equatable {
    case revokedRemotely
    case localOnly(reason: String)            // provider không hỗ trợ / lỗi mạng khi xóa account
}

public struct RemovalReport: Sendable, Equatable {
    public var revocations: [CredentialID: RevocationOutcome]
    public var leftoverSecrets: [SecretID]    // xóa Keychain thất bại — UI cảnh báo
}

public enum ScopeServiceError: Error, Sendable, Equatable {
    case notSubset(extra: ScopeSet)               // reduce với scope không có
    case grantWideRevocationNotAcknowledged
    case credentialNotFound(CredentialID)
}

public actor ScopeService {
    public static let dropboxConsoleURL = URL(string: "https://www.dropbox.com/developers/apps")!
    public init(login: any LoginRunner, providers: any ProviderRegistry,
                clients: any OAuthClientRepository, accounts: any AccountRepository,
                credentials: any CredentialRepository, secrets: SecretVault, audit: any AuditLog,
                tokenEndpoint: TokenEndpointClient, tokens: TokenProvider, clock: any DateProvider)

    public func missingScopes(_ account: AccountID) async throws -> ScopeSet
    public func planGrantMore(_ account: AccountID, adding extra: ScopeSet = []) async throws -> GrantMorePlan
    /// Điểm vào DUY NHẤT cho mọi login từ UI (thêm account, re-auth, cấp thêm, thu hẹp).
    public func execute(_ request: LoginRequest) async throws -> LoginOutcome
    public func reduce(_ account: AccountID, to scopes: ScopeSet) async throws -> LoginOutcome
    public func revoke(_ credential: CredentialID, acknowledgeGrantWideRevocation: Bool) async throws -> RevocationOutcome
    public func removeAccount(_ account: AccountID, acknowledgeGrantWideRevocation: Bool) async throws -> RemovalReport
}
```

### 3. Hành vi

**`missingScopes`**: `canonical(provider.defaultScopes).missing(in: active.grantedScopes)`.

**`planGrantMore(account, adding)`**: `need = canonical(defaultScopes ∪ adding)`,
`missing = need.missing(in: granted)`; rỗng → `.nothingMissing`. Theo `quirks.incrementalAuth`:

| Style | LoginRequest |
| --- | --- |
| `.includeGrantedScopes` | `scopes = missing ∪ {openid, email}`, `includeGrantedScopes = true`, `target = .existing`, `loginHint = email` |
| `.reauthorize` | `scopes = granted ∪ missing`, `target = .existing`, `loginHint = email` |
| `.consoleThenRelogin` | `.consoleThenRelogin(consoleURL, missing, then: scopes = need, target = .existing)` |

**`execute(request)`**:
1. `outcome = login.login(request)`.
2. `tokens.invalidate(account)`; `try await tokens.forceRefresh(account)` — thành công →
   `cleanupSuperseded(account)`; lỗi → bỏ qua dọn (giữ secret cũ), **không** throw (login đã thành
   công; health check sẽ báo).
3. Trả `outcome`.

**`cleanupSuperseded(account)`** (private): mọi credential `superseded` còn giá trị Keychain
(`secrets.exists`) → `secrets.purgeValue(ref, actor: .app)`. Hàng credential và metadata secret
giữ nguyên (FK `refresh_token_ref` là RESTRICT, và giữ lịch sử).

**Bổ sung SPEC-004** (T22 làm, test U14): thêm vào `SecretVault`
`public func purgeValue(_ id: SecretID, actor: AuditActor) async throws` — xóa item Keychain,
giữ metadata, đặt `rotatedAt = now`, audit `secretDeleted`.

**`reduce(account, to)`**: `extra = to.missing(in: granted)` ≠ ∅ → `.notSubset`. Login với
`scopes = to`, `includeGrantedScopes = false`, `.existing`. Sau khi `execute` xong: nếu
`revocation` của provider là `.dropboxAPI` → thu hồi credential cũ (đọc RT cũ → refresh lấy access
token → revoke) trước khi purge. Audit `scopeReduced` (scopes = phần bị bỏ).

**`revoke(credential, ack)`**:

| `RevocationStyle` | Hành động |
| --- | --- |
| `.rfc7009(url, revokesWholeGrant: true)` | `ack == false` → throw `.grantWideRevocationNotAcknowledged`. Ngược lại revoke **refresh token** (`token_type_hint=refresh_token`); đánh dấu MỌI credential active/superseded của account là `revoked`; account `needsReauth` |
| `.rfc7009(url, false)` | revoke refresh token của credential đó |
| `.dropboxAPI` | refresh bằng RT → access token → revoke bằng Bearer |
| `.unsupported` | không gọi mạng → `.localOnly("provider không hỗ trợ thu hồi")` |

Sau đó: `markRevoked`, `purgeValue` secret, `tokens.invalidate`, audit `credentialRevoked`. Nếu
account không còn credential active → `updateStatus(.needsReauth)`.
Lỗi mạng khi revoke → throw (người dùng thử lại), **trừ** khi gọi từ `removeAccount`.

**`removeAccount(account, ack)`**:
1. Liệt kê credential; với Google (`revokesWholeGrant`) chỉ revoke **một lần** (credential active
   hoặc mới nhất) — cần `ack`, thiếu → throw trước khi làm gì.
2. Mỗi revoke lỗi mạng → `.localOnly("network")`, tiếp tục.
3. Thu thập `secretIds` của mọi credential; `accounts.delete` (cascade credential + health);
   rồi `secrets.delete` từng secret (giờ không còn FK) — lỗi → `leftoverSecrets`.
4. `tokens.invalidate`; audit `accountRemoved`.

## Implementation Steps

1. **T22 (GLM-5.3)** — toàn bộ + `SecretVault.purgeValue`. U1–U14.

## Testing

See ./TESTING.md. Seam: `LoginRunner` (fake trả outcome dựng sẵn, ghi lại request).

## Risks and Rollback

- Thu hồi Google nhầm → người dùng phải đăng nhập lại (có xác nhận `ack` bắt buộc).

## Open Questions

- Không có.
