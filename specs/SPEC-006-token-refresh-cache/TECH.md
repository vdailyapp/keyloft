# SPEC-006: Refresh, xoay vòng và cache — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

Actor Swift có reentrancy: giữa hai `await` trong cùng actor, lời gọi khác có thể chen vào. Không
cẩn thận thì kiểm tra "đang refresh chưa?" xong rồi `await` sẽ sinh hai refresh. Ngoài ra nếu task
refresh là con của caller, caller bị hủy → refresh bị hủy giữa chừng sau khi provider đã xoay token
→ mất token.

## Relevant Code

- `Sources/TokenVault/TokenEndpointClient.swift` — `refresh(...)` (SPEC-005 §5)
- `Sources/TokenVault/ScopeNormalizer.swift` (SPEC-005 §3)
- `Sources/SecretVault/SecretVault.swift` — `read`, `rotate` (SPEC-004 §3)
- `Sources/VaultDomain/Repositories.swift` — `CredentialRepository.active`, `updateGrantedScopes`,
  `AccountRepository.updateStatus`

## Current State

Sau SPEC-005: có `TokenEndpointClient` và `OAuthLoginService` (gọi `onCredentialIssued`).

## Proposed Changes

### 1. File

```
Sources/TokenVault/TokenProvider.swift
Sources/TokenVault/TokenVaultError.swift
```

### 2. Interface

```swift
public enum TokenVaultError: Error, Sendable, Equatable {
    case accountNotFound(AccountID)
    case noActiveCredential(AccountID)
    case oauth(OAuthError)                    // giữ nguyên lỗi gốc để caller xét isTransient
    case secret(String)                       // đọc refresh token lỗi (bọc SecretVaultError, không lộ giá trị)
    case rotationPersistFailed(AccountID)
}

public actor TokenProvider {
    public static let defaultMinValidity: TimeInterval = 60
    public static let rotationRetries = 3

    public init(providers: any ProviderRegistry, clients: any OAuthClientRepository,
                accounts: any AccountRepository, credentials: any CredentialRepository,
                secrets: SecretVault, audit: any AuditLog,
                tokenEndpoint: TokenEndpointClient, clock: any DateProvider)

    public func accessToken(for account: AccountID,
                            minValidity: TimeInterval = defaultMinValidity) async throws -> AccessToken
    /// Bỏ qua cache (health check tầng 2). Vẫn single-flight với accessToken().
    public func forceRefresh(for account: AccountID) async throws -> AccessToken
    public func seed(_ token: AccessToken, for account: AccountID)     // dùng làm onCredentialIssued
    public func invalidate(_ account: AccountID)
    public func cachedToken(for account: AccountID) -> AccessToken?    // cho test/health, không refresh
}
```

### 3. Single-flight

```swift
private var cache: [AccountID: AccessToken] = [:]
private var inFlight: [AccountID: Task<AccessToken, any Error>] = [:]

func accessToken(for id, minValidity) async throws -> AccessToken {
    if let t = cache[id], t.isValid(at: clock.now(), minValidity: minValidity) { return t }
    return try await joinOrStartRefresh(id)
}
private func joinOrStartRefresh(_ id) async throws -> AccessToken {
    if let task = inFlight[id] { return try await task.value }   // không có await trước dòng này → không race
    let task = Task { try await self.performRefresh(id) }        // unstructured: caller hủy không hủy task
    inFlight[id] = task
    defer { inFlight[id] = nil }   // chạy sau khi await xong (vẫn trong actor)
    return try await task.value
}
```

Lưu ý: `defer` xóa `inFlight` sau `await` — đúng vì chỉ caller khởi tạo mới xóa, và các caller
khác đã giữ tham chiếu `task`. Chờ `task.value` của unstructured task không lan truyền hủy: caller
bị hủy vẫn chờ tới khi refresh xong (chấp nhận được, refresh < vài giây). Ghi comment trong code.

### 4. performRefresh

1. `account` (nil → `.accountNotFound`); `credential = credentials.active` (nil → `.noActiveCredential`).
2. `client`, `provider`; `clientSecret` (nếu có) qua `secrets.read(..., actor: .app)`.
3. `rt = secrets.read(credential.refreshTokenRef, reason: "Làm mới token", actor: .app)`.
4. `resp = tokenEndpoint.refresh(rt, tokenURL: provider.tokenURL, client:,
   scopes: provider.quirks.refreshIncludesScope ? credential.grantedScopes : nil)`.
5. Lỗi:
   - `.invalidGrant` → `accounts.updateStatus(.needsReauth)`, `cache[id] = nil`, audit
     `tokenRefreshFailed` (`result: .failure("invalid_grant")`), throw `.oauth(err)`.
   - `.invalidClient` → `updateStatus(.degraded)`, audit như trên, throw.
   - `isTransient` → throw `.oauth(err)` **không** đổi status, không audit.
   - khác → throw `.oauth(err)`.
6. Xoay vòng: `resp.refreshToken` khác nil và khác `rt` → `secrets.rotate(ref, to:, actor: .app)`
   thử tối đa 3 lần; vẫn lỗi → `updateStatus(.needsReauth)`, throw `.rotationPersistFailed`.
   (Áp dụng cho mọi provider trả RT mới, không chỉ khi `rotatesRefreshToken`.)
7. Scope: `resp.scope != nil` → `granted = ScopeNormalizer.granted(...)`; nếu
   `credential.grantedScopes.missing(in: granted)` ≠ ∅ → `updateGrantedScopes`, audit `scopeReduced`
   (scopes = phần bị mất). Nếu granted rộng hơn → cũng cập nhật, không audit.
8. `token = AccessToken(value: resp.accessToken, scopes: granted ?? credential.grantedScopes,
   expiresAt: now + TimeInterval(resp.expiresIn ?? 3600))`; `cache[id] = token`; return.

Refresh thành công không ghi audit (tránh ngập log); không tự đổi status về `healthy` (việc của
SPEC-008).

## Implementation Steps

1. **T16 (GLM-5.3)** — toàn bộ. U1–U14.

## Testing

See ./TESTING.md. Seam: `StubHTTPClient` có route với độ trễ (`Task.sleep` trong `respond`) để
tạo cửa sổ race.

## Risks and Rollback

- Deadlock nếu `performRefresh` gọi lại `accessToken` cùng account → cấm (review).

## Open Questions

- Giới hạn cache theo số account? Không cần (vài chục account).
