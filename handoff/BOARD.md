# Task board — Keyloft giai đoạn 1

Status: `todo` → `in-progress:<phiên>` → `review` → `done` (hoặc `blocked`, `changes-requested`,
`needs-human`). Chỉ sửa trên `main`, mỗi thay đổi một commit `board: Txx <status>`. Quy trình: [README.md](README.md). Model: **5.3** = GLM-5.3, Flash = GLM-5.3-Flash.

Tổng 30 task: 10 GLM-5.3, 20 Flash. Từ T27 trở đi mọi task và cả phiên Lead chạy GLM-5.3-Flash.

| Task | Tiêu đề | Spec | Model | Wave | Deps | Status |
| --- | --- | --- | --- | --- | --- | --- |
| [T01](tasks/T01-spm-skeleton.md) | Khung SPM, Makefile, lint, CI | SPEC-001 | Flash | 0 | — | done |
| [T02](tasks/T02-domain-entities.md) | VaultDomain: ID, enum, ScopeSet, entity | SPEC-002 | Flash | 1 | T01 | done |
| [T03](tasks/T03-domain-protocols-testsupport.md) | VaultDomain: protocol repo/infra + KeyloftTestSupport | SPEC-002 | Flash | 2 | T02 | done |
| [T04](tasks/T04-persistence-schema.md) | VaultPersistence: VaultDatabase, migration v1, record | SPEC-003 | **5.3** | 3 | T03 | done |
| [T05](tasks/T05-core-repos.md) | VaultPersistence: repo OAuthClient, Account, Credential, SecretMetadata | SPEC-003 | Flash | 4 | T04 | done |
| [T06](tasks/T06-health-audit-repos.md) | VaultPersistence: repo HealthCheck (retention 50) + AuditLog | SPEC-003 | Flash | 4 | T04 | done |
| [T07](tasks/T07-secret-vault-facade.md) | SecretVault: protocol SecretStore, facade, InMemorySecretStore | SPEC-004 | Flash | 3 | T03 | done |
| [T08](tasks/T08-keychain-store.md) | SecretVault: KeychainSecretStore (SecItem, access control) | SPEC-004 | **5.3** | 4 | T07 | done |
| [T09](tasks/T09-vault-lock.md) | SecretVault: VaultLock + LocalAuthenticationAuthenticator | SPEC-004 | **5.3** | 5 | T08 | done |
| [T10](tasks/T10-pkce-state.md) | TokenVault: Base64URL, PKCE, state | SPEC-005 | Flash | 3 | T03 | done |
| [T11](tasks/T11-authorize-url-scopes.md) | TokenVault: AuthorizationRequest + ScopeNormalizer | SPEC-005 | Flash | 4 | T10 | done |
| [T12](tasks/T12-loopback-browser.md) | TokenVault: LoopbackServer (NWListener) + BrowserSession + fakes | SPEC-005 | **5.3** | 2 | T02 | done |
| [T13](tasks/T13-token-endpoint.md) | TokenVault: TokenEndpointClient, OAuthError, form encoding | SPEC-005 | Flash | 3 | T03 | done |
| [T14](tasks/T14-id-token.md) | TokenVault: IDTokenClaims decode + validate | SPEC-005 | Flash | 4 | T10, T13 | done |
| [T15](tasks/T15-oauth-login-service.md) | TokenVault: OAuthLoginService (điều phối đăng nhập) | SPEC-005 | **5.3** | 5 | T07, T10, T11, T12, T13, T14 | done |
| [T16](tasks/T16-token-provider.md) | TokenVault: TokenProvider (cache, single-flight, rotation) | SPEC-006 | **5.3** | 5 | T07, T11, T13 | done |
| [T17](tasks/T17-provider-catalog.md) | Providers: Google, Microsoft, Dropbox + ProviderCatalog | SPEC-007 | Flash | 3 | T03 | done |
| [T18](tasks/T18-oidc-discovery.md) | Providers: OIDC Discovery + merge an toàn | SPEC-007 | Flash | 4 | T17 | done |
| [T19](tasks/T19-api-probes.md) | Providers: API probe Google/Microsoft/Dropbox | SPEC-007 | Flash | 4 | T17 | done |
| [T20](tasks/T20-health-checker.md) | HealthCheck: 5 tầng + map trạng thái | SPEC-008 | **5.3** | 6 | T16, T19 | done |
| [T21](tasks/T21-health-scheduler.md) | HealthCheck: HealthScheduler (trigger, 6h, backoff, dedupe) | SPEC-008 | **5.3** | 7 | T20 | done |
| [T22](tasks/T22-scope-service.md) | TokenVault: ScopeService (cấp thêm, thu hẹp, thu hồi, xóa account) | SPEC-009 | **5.3** | 6 | T15, T16 | done |
| [T23](tasks/T23-vault-runtime.md) | VaultRuntime: composition root + test tích hợp GRDB | SPEC-010 | Flash | 8 | T05, T06, T09, T18, T21, T22 | done |
| [T24](tasks/T24-cli.md) | KeyloftCLI: accounts, health, token | SPEC-010 | Flash | 9 | T23 | done |
| [T25](tasks/T25-app-shell.md) | App: XcodeGen, ký, entitlement, WebAuth, AppContainer, lifecycle | SPEC-011 | **5.3** | 9 | T23 | done |
| [T26](tasks/T26-ui-menubar-accounts.md) | App: Menu bar + Accounts + notification | SPEC-011 | Flash | 10 | T25 | done |
| [T27](tasks/T27-ui-oauth-clients.md) | App: OAuth Clients (Providers) | SPEC-011 | Flash | 10 | T25 | done |
| [T28](tasks/T28-ui-secrets-health-audit.md) | App: Secrets (Touch ID), Health history, Audit | SPEC-011 | Flash | 10 | T25 | done |
| [T29](tasks/T29-security-review-e2e.md) | Review bảo mật (RFC 9700/MASVS) + E2E thủ công 3 provider | SPEC-005..011 | Flash | 11 | T24, T26, T27, T28, T30 | needs-human |
| [T30](tasks/T30-hardening-cleanup.md) | Dọn nợ review: `try?` nuốt lỗi, print debug, lint chặn | SPEC-003..011 | Flash | 10 | T26 | done |

## Ghi chú thay đổi interface

Khi task đổi public API mà task khác đã/đang dùng, ghi một dòng ở đây: `Txx: đổi X → Y, ảnh hưởng Tyy`.

- (đã chốt sẵn trong spec) T08: `KeychainSecretStore.init(configuration:contextProvider:)` nhận `KeychainAuthContextProvider` thay vì `VaultLock`.
- T12: `BrowserSession` throw `BrowserSessionError.userCancelled`; T15 map sang `OAuthError.userCancelled`.
- T09: `KeychainAuthContextProvider.currentContext()` đổi trả `AuthenticatedContext?` (wrapper Sendable) thay `LAContext?` — LAContext không gửi qua actor được trong Swift 6; ảnh hưởng T08 (đã cập nhật trong cùng PR).
- T23: `RuntimeDependencies.secretStore` là factory `(any KeychainAuthContextProvider) -> any SecretStore` (Keychain cần VaultLock do init dựng); thêm `RuntimeDependencies.inMemory(...)` cho test tích hợp.
- T20: `HealthChecker` nhận `secretExists: @Sendable (SecretID) async throws -> Bool` thay `secrets: SecretVault` (HealthCheck không được phụ thuộc SecretVault trong Package.swift); T23 bơm closure từ SecretVault. Ghi chú thêm: T16 `TokenProvider.init` có tham số `ids: any IDGenerator` (TECH thiếu, audit cần).
- main (review 2026-10-26): CLI embed chuyển `Contents/MacOS/keyloft` → `Contents/Helpers/keyloft` (APFS không phân biệt hoa thường: bản cũ ghi đè binary `Keyloft` của app). `CLIInstaller`, `Makefile embed-cli`, SPEC-010 đã cập nhật; T29 dùng đường dẫn mới.
- T30: `HealthScheduler.run(_:)` giờ `async throws` (caller scheduled tự bắt vào `lastRunError`); `LoginOutcome` thêm field `narrowRevocationFailed: Bool = false` (reduce Dropbox báo thu hồi provider thất bại) — ảnh hưởng caller của `scheduler.run` và test so sánh `LoginOutcome`.
