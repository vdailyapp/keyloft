# SPEC-008: Health check — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

Logic map lỗi → trạng thái là chỗ dễ sai nhất và quyết định niềm tin của người dùng; phải là một
hàm thuần, test bằng bảng. Scheduler phụ thuộc thời gian thật → phải tiêm clock + sleeper.

## Relevant Code

- `Sources/TokenVault/TokenProvider.swift` — `forceRefresh`, `TokenVaultError` (SPEC-006)
- `Sources/TokenVault/OAuthError.swift` — `isTransient` (SPEC-005 §5)
- `Sources/TokenVault/ScopeNormalizer.swift` — `canonical` (SPEC-005 §3)
- `Sources/Providers/APIProbe.swift` — `APIProbe`, `ProbeError`, `ProbeFactory` (SPEC-007 §4)
- `Sources/VaultDomain/HealthCheckResult.swift`, `Repositories.swift`

## Current State

Placeholder `Sources/HealthCheck/HealthCheck.swift`.

## Proposed Changes

### 1. File

```
Sources/HealthCheck/
├── HealthPolicy.swift
├── HealthOutcome.swift        # LayerOutcome + hàm thuần statusFor(...)
├── HealthChecker.swift        # T20
├── HealthScheduler.swift      # T21
└── Sleeper.swift              # T21: protocol + TaskSleeper
```

### 2. Policy & hàm thuần (T20)

```swift
public struct HealthPolicy: Sendable, Equatable {
    public var quotaWarnRatio: Double = 0.9
    public var secretExpiryWarn: TimeInterval = 30 * 86_400
    public var slowThresholdMs: Int = 3_000
    public var freshnessForHeavyTask: TimeInterval = 15 * 60
}

enum LayerFailure: Sendable, Equatable {
    case noRefreshToken
    case refreshInvalidGrant, refreshInvalidClient, refreshTransient(String), refreshOther(String)
    case apiInsufficientScope(String?), apiTransient(String), apiRejected(String)
    case missingScopes(ScopeSet)
}
/// Thuần: tầng lỗi đầu tiên (nếu có) + cảnh báo → trạng thái.
func status(for failure: LayerFailure?, warnings: [String]) -> AccountStatus
```

Map: `noRefreshToken, refreshInvalidGrant` → `.needsReauth`; `refreshInvalidClient, refreshOther,
apiRejected` → `.degraded`; `refreshTransient, apiTransient` → `.unreachable`;
`apiInsufficientScope, missingScopes` → `.needsConsent`; `nil` + warnings ≠ ∅ → `.degraded`;
`nil` + ∅ → `.healthy`.

Map lỗi vào `LayerFailure`:

- `TokenVaultError.noActiveCredential` → `noRefreshToken`
- `.oauth(.invalidGrant)`, `.rotationPersistFailed` → `refreshInvalidGrant`
- `.oauth(.invalidClient)` → `refreshInvalidClient`
- `.oauth(e)` với `e.isTransient` → `refreshTransient`
- `.secret(...)` (Keychain đọc lỗi, vd `interactionNotAllowed` khi máy khóa) → `refreshTransient`
  (**không** phải needsReauth: token vẫn còn, chỉ là chưa đọc được)
- còn lại → `refreshOther`
- `ProbeError.insufficientScope` → `apiInsufficientScope`; `isTransient` → `apiTransient`;
  `.unauthorized, .forbidden, .malformed` → `apiRejected`

### 3. HealthChecker (T20)

```swift
public typealias ProbeResolver = @Sendable (ProviderID) -> any APIProbe

public actor HealthChecker {
    public init(accounts: any AccountRepository, credentials: any CredentialRepository,
                clients: any OAuthClientRepository, secrets: SecretVault, tokens: TokenProvider,
                providers: any ProviderRegistry, probes: @escaping ProbeResolver,
                results: any HealthCheckRepository, audit: any AuditLog,
                clock: any DateProvider, ids: any IDGenerator, policy: HealthPolicy = .init())
    public func check(_ account: AccountID, actor: AuditActor) async throws -> HealthCheckResult
}
```

`check` (chỉ throw khi account không tồn tại hoặc DB lỗi; lỗi của tầng là dữ liệu, không throw):

1. **tokenPresent**: `credentials.active` có và `secrets.exists(ref)` → ok; không → failure.
2. **refresh**: `tokens.forceRefresh(for:)`, đo `latencyMs`.
3. **apiCall**: `probes(provider.id).probe(accessToken: token.value)`.
4. **scopes**: `required = ScopeNormalizer.canonical(provider.defaultScopes, provider:)`;
   `missing = required.missing(in: credential.grantedScopes)` (dùng credential đọc lại **sau**
   bước 2 vì refresh có thể cập nhật scope).
5. **earlyWarning**: `quota.total` có và `used/total > 0.9` → `"quota>90%"`; client
   `secretExpiresAt - now < 30 ngày` → `"clientSecret<30d"` (đã quá hạn → `"clientSecretExpired"`);
   `probe.latencyMs > slowThresholdMs` → `"slow"`.
6. Tầng sau tầng lỗi đầu tiên **không chạy** và **không có** trong `checks` (mảng chỉ chứa các tầng
   đã chạy). `error` của item = mô tả đã làm sạch (không chứa token; dùng tên case lỗi).
7. Lưu `HealthCheckResult` (`results.append`); status khác `account.status` →
   `accounts.updateStatus` + audit `accountStatusChanged` (target `account:<id>`, result success,
   actor theo tham số).

### 4. HealthScheduler (T21)

```swift
public protocol Sleeper: Sendable { func sleep(for duration: Duration) async throws }
public struct TaskSleeper: Sleeper { ... Task.sleep(for:) }

public enum HealthTrigger: Sendable, Equatable {
    case appLaunch, wake, periodic, manual(AccountID?), retry(AccountID)
}

public actor HealthScheduler {
    public static let backoff: [TimeInterval] = [60, 120, 240, 480, 960, 1800]  // sau đó giữ 1800
    public init(checker: HealthChecker, accounts: any AccountRepository, results: any HealthCheckRepository,
                clock: any DateProvider, sleeper: any Sleeper,
                interval: TimeInterval = 6 * 3600, maxConcurrent: Int = 3, policy: HealthPolicy = .init())
    /// Bắt đầu vòng định kỳ + tiêu thụ trigger ngoài (App đẩy appLaunch/wake). Gọi một lần.
    public func start(external: AsyncStream<HealthTrigger>)
    public func stop()
    /// Chạy ngay; trả kết quả theo thứ tự account. Dedupe theo account đang chạy.
    @discardableResult public func run(_ trigger: HealthTrigger) async -> [HealthCheckResult]
    /// Trước tác vụ lớn: kết quả < freshness và healthy/degraded → trả luôn; ngược lại check.
    public func ensureFresh(_ account: AccountID) async throws -> HealthCheckResult
    public nonisolated var updates: AsyncStream<HealthCheckResult> { get }   // cho UI/menu bar
}
```

- Dedupe: `running: [AccountID: Task<HealthCheckResult, any Error>]` (cùng pattern SPEC-006).
- Concurrency: `withTaskGroup`, tối đa `maxConcurrent` task cùng lúc (thêm task mới khi một task xong).
- Backoff: kết quả `unreachable` → `retryCount[id] += 1`, lên lịch `retry(id)` sau
  `backoff[min(n-1, last)]` bằng `sleeper`; kết quả khác → `retryCount[id] = 0`, hủy retry đang chờ.
- Định kỳ: task lặp `sleeper.sleep(interval)` → `run(.periodic)`.
- Actor audit: `.scheduler` cho appLaunch/wake/periodic/retry; `.user` cho manual.
- Không import AppKit: sự kiện wake do App đẩy vào `external` (SPEC-011).

## Implementation Steps

1. **T20 (GLM-5.3)** — §2, §3. U1–U18.
2. **T21 (GLM-5.3)** — §4. U19–U26, I1.

## Testing

See ./TESTING.md. Seam: `ProbeResolver`, `Sleeper` (fake: `ManualSleeper` — sleep chỉ trả về khi
test gọi `advance(by:)`), `FixedDateProvider`.

## Risks and Rollback

- `forceRefresh` ở tầng 2 tạo thêm 4 refresh/ngày/account — chấp nhận được (giới hạn provider
  cao hơn nhiều).

## Open Questions

- Health check có nên dùng access token cache thay vì force refresh? Không: mục đích tầng 2 là
  chứng minh refresh token còn sống.
