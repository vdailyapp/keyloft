# SPEC-010: VaultRuntime và CLI — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

Composition root phải là nơi duy nhất biết GRDB và `KeychainSecretStore`, và vẫn test được bằng
fake (InMemorySecretStore, StubHTTPClient) mà `VaultRuntime` không phụ thuộc `KeyloftTestSupport`.

## Relevant Code

- `Sources/VaultPersistence/VaultDatabase.swift`, `Repositories/*` (SPEC-003)
- `Sources/SecretVault/{SecretVault,KeychainSecretStore,VaultLock}.swift` (SPEC-004)
- `Sources/TokenVault/{OAuthLoginService,TokenProvider,ScopeService}.swift` (SPEC-005/006/009)
- `Sources/Providers/{ProviderCatalog,APIProbe}.swift` (SPEC-007)
- `Sources/HealthCheck/{HealthChecker,HealthScheduler}.swift` (SPEC-008)

## Current State

Mọi service tồn tại riêng lẻ; chưa có chỗ lắp ráp. `KeyloftCLI` in version.

## Proposed Changes

### 1. VaultRuntime (T23)

```
Sources/VaultRuntime/
├── RuntimeConfiguration.swift
├── VaultRuntime.swift
└── UnavailableBrowserSession.swift   # CLI: throw OAuthError.userCancelled kèm thông điệp
```

```swift
public enum RuntimeContext: Sendable { case app, cli }

public struct RuntimeConfiguration: Sendable {
    public var databaseURL: URL
    public var keychain: KeychainConfiguration
    public var healthPolicy: HealthPolicy
    /// app: Data Protection Keychain; cli: giống app, trừ khi KEYLOFT_DEV_LOGIN_KEYCHAIN=1.
    public static func `default`(for context: RuntimeContext,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) throws -> RuntimeConfiguration
}

public struct RuntimeDependencies: Sendable {      // seam cho test
    public var database: VaultDatabase
    public var secretStore: any SecretStore
    public var http: any HTTPClient
    public var browser: any BrowserSession
    public var authenticator: any UserPresenceAuthenticator
    public var clock: any DateProvider = SystemDateProvider()
    public var ids: any IDGenerator = SystemIDGenerator()
    public var random: any RandomSource = SystemRandomSource()
    public var sleeper: any Sleeper = TaskSleeper()
    public var receivers: CallbackReceiverFactory = { LoopbackServer(configuredRedirect: $0) }
}

public final class VaultRuntime: Sendable {
    public let accounts: any AccountRepository
    public let clients: any OAuthClientRepository
    public let credentials: any CredentialRepository
    public let healthResults: any HealthCheckRepository
    public let audit: any AuditLog
    public let providers: ProviderCatalog
    public let secrets: SecretVault
    public let lock: VaultLock
    public let tokens: TokenProvider
    public let login: OAuthLoginService
    public let scopes: ScopeService
    public let health: HealthChecker
    public let scheduler: HealthScheduler
    public let clock: any DateProvider

    public init(_ deps: RuntimeDependencies, policy: HealthPolicy = .init())
    /// Production: mở DB file, KeychainSecretStore theo config, URLSessionHTTPClient (ephemeral).
    public static func live(context: RuntimeContext, browser: any BrowserSession) throws -> VaultRuntime
}
```

Thứ tự dựng trong `init`: repos (GRDB từ `deps.database`) → `ProviderCatalog` (với
`OIDCDiscovery(http:)`) → `VaultLock` → `SecretVault` → `TokenEndpointClient` → `TokenProvider` →
`OAuthLoginService(onCredentialIssued: { [tokens] id, t in await tokens.seed(t, for: id) })` →
`ScopeService` → `HealthChecker(probes: { ProbeFactory.probe(for: $0, http:, clock:) })` →
`HealthScheduler`.

`live(context: .cli)`: DB chưa tồn tại → throw `RuntimeError.vaultNotInitialized` (CLI không tạo
DB). `KeychainSecretStore` lỗi `missingEntitlement` lần đầu → bọc thành
`RuntimeError.keychainUnavailable(hint:)` với gợi ý `KEYLOFT_DEV_LOGIN_KEYCHAIN=1`.

### 2. CLI (T24)

```
Sources/KeyloftCLI/
├── Keyloft.swift              # @main struct Keyloft: AsyncParsableCommand, subcommands
├── AccountsCommand.swift
├── HealthCommand.swift
├── TokenCommand.swift
├── AccountSelector.swift      # thuần: resolve(_ query: String, in: [Account]) -> Result
├── Output.swift               # TableFormatter, JSON DTO, StandardStreams protocol (stdout/stderr ghi được trong test)
└── ExitCodes.swift            # enum KeyloftExitCode: Int32 + from(AccountStatus)
```

```swift
public enum SelectorError: Error, Equatable { case notFound(String), ambiguous([Account]) }
public enum AccountSelector {
    public static func resolve(_ query: String, in accounts: [Account]) -> Result<Account, SelectorError>
}
enum KeyloftExitCode: Int32 { case ok = 0, failure = 1, needsReauth = 2, needsConsent = 3, unreachable = 4, usage = 64
    static func from(_ status: AccountStatus) -> KeyloftExitCode
    static func worst(_ statuses: [AccountStatus]) -> KeyloftExitCode }   // theo severity
```

- Command nhận `runtimeFactory` để test (`static var makeRuntime: @Sendable () throws -> VaultRuntime = { try .live(context: .cli, browser: UnavailableBrowserSession()) }`).
- `token`: `runtime.tokens.accessToken(for:minValidity:)` hoặc `forceRefresh`; ghi audit
  `tokenIssued` (actor `.cli`, target `account:<id>`, scopes = token.scopes) **trước** khi in.
- `health`: gọi thẳng `runtime.health.check(id, actor: .cli)` trong task group giới hạn 3; không
  dùng scheduler (CLI không `start` scheduler).
- JSON health DTO: `{account: {id, provider, email}, status, checkedAt (ISO8601), checks: [{name, ok, latencyMs, error, warnings}]}`.

## Implementation Steps

1. **T23 (Flash)** — §1 + `VaultRuntimeTests` I1–I3.
2. **T24 (Flash)** — §2 + `KeyloftCLITests` U1–U12.

## Testing

See ./TESTING.md.

## Risks and Rollback

- `URLSession.shared` có cache/cookie → dùng `URLSessionConfiguration.ephemeral`.

## Open Questions

- Không có.
