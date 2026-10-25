# SPEC-011: App macOS — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

SPM không tạo được `.app` có entitlement, Info.plist, embed CLI và ký. `ASWebAuthenticationSession`
cần presentation anchor (AppKit) và phải phối hợp với loopback server (SPEC-005 §4).

## Relevant Code

- `Sources/VaultRuntime/VaultRuntime.swift` — `VaultRuntime.live(context: .app, browser:)` (SPEC-010)
- `Sources/TokenVault/BrowserSession.swift` — protocol (SPEC-005 §4)
- `Sources/TokenVault/ScopeService.swift` — mọi hành động account (SPEC-009)
- `Sources/HealthCheck/HealthScheduler.swift` — `start(external:)`, `updates` (SPEC-008)
- `Sources/SecretVault/VaultLock.swift` — `unlock`, `lock`, `states()` (SPEC-004)

## Current State

Chưa có `App/`.

## Proposed Changes

### 1. Cây thư mục

```
App/
├── project.yml                  # XcodeGen: target Keyloft (app) phụ thuộc package local ".."
├── Keyloft.entitlements         # keychain-access-groups: $(AppIdentifierPrefix)app.vdaily.keyloft
├── Info.plist                   # LSUIElement = YES (chỉ menu bar), CFBundleURLTypes: app.vdaily.keyloft
├── KeyloftApp.swift             # @main App: MenuBarExtra + Window + Settings
├── AppContainer.swift           # @MainActor: giữ VaultRuntime, AsyncStream trigger, wiring lifecycle
├── Platform/
│   ├── WebAuthBrowserSession.swift    # BrowserSession bằng ASWebAuthenticationSession
│   ├── SystemEvents.swift             # NSWorkspace notifications → HealthTrigger / VaultLock.lock()
│   ├── Notifier.swift                 # UNUserNotificationCenter, dedupe 24h
│   ├── Clipboard.swift                # copy + xóa sau 60 s nếu nội dung chưa đổi (changeCount)
│   └── CLIInstaller.swift             # symlink /usr/local/bin/keyloft
├── Features/
│   ├── MenuBar/   MenuBarView.swift, MenuBarModel.swift, MenuBarBadge.swift
│   ├── Accounts/  AccountsView.swift, AccountDetailView.swift, AddAccountFlow.swift, AccountsModel.swift, AccountDetailModel.swift
│   ├── Providers/ OAuthClientsView.swift, OAuthClientForm.swift, OAuthClientsModel.swift
│   ├── Secrets/   SecretsView.swift, SecretsModel.swift, UnlockGate.swift
│   ├── Health/    HealthHistoryView.swift, HealthHistoryModel.swift
│   └── Audit/     AuditView.swift, AuditModel.swift
└── Tests/KeyloftAppTests/       # unit test model (target test trong project.yml, Swift Testing)
```

Build script: `make app` = `xcodegen generate --spec App/project.yml && xcodebuild -scheme Keyloft build`.
Thêm vào Makefile ở T25 (ngoại lệ được phép sửa Makefile, không sửa `Package.swift`).

### 2. project.yml (T25)

- Target `Keyloft` (application, macOS 14), dependency package local `path: ..`, product
  `VaultRuntime`.
- Bước "Copy Files" embed executable `keyloft` (product từ package) vào `Contents/MacOS/`, ký cùng
  identity + cùng entitlements file (`codesign --entitlements`, có `com.apple.application-identifier`
  cần thiết cho data-protection keychain → dùng provisioning profile Developer ID, ghi trong
  README/T25 report).
- `DEVELOPMENT_TEAM` đọc từ `App/Local.xcconfig` (gitignored), có `Local.xcconfig.example`.
- Hardened runtime bật. Không App Sandbox ở giai đoạn 1 (DB ở Application Support; CLI cần cùng đường dẫn).

### 3. WebAuthBrowserSession (T25)

```swift
@MainActor final class WebAuthBrowserSession: NSObject, BrowserSession, ASWebAuthenticationPresentationContextProviding {
    nonisolated func present(_ url: URL, callbackScheme: String) async throws
}
```

- `ASWebAuthenticationSession(url:, callback: .customScheme(callbackScheme))`,
  `prefersEphemeralWebBrowserSession = false` (cho phép SSO sẵn có), `presentationContextProvider = self`.
- Lỗi `.canceledLogin` → `BrowserSessionError.userCancelled`. Hoàn tất với URL `app.vdaily.keyloft://oauth-complete`
  → return. Task bị hủy (loopback xong trước) → `session.cancel()` qua `withTaskCancellationHandler`.

### 4. AppContainer & lifecycle (T25)

```swift
@MainActor @Observable final class AppContainer {
    let runtime: VaultRuntime
    private(set) var latestStatuses: [AccountID: AccountStatus]   // cập nhật từ scheduler.updates
    var lockState: VaultLockState
    init() throws        // VaultRuntime.live(context: .app, browser: WebAuthBrowserSession())
    func start()         // scheduler.start(external: triggers); đẩy .appLaunch; observe SystemEvents
}
```

`SystemEvents`: `didWakeNotification` → `.wake`; `willSleepNotification`, `screensDidSleepNotification`,
`sessionDidResignActiveNotification` → `runtime.lock.lock()`. Dùng `NotificationCenter.notifications(named:)`
(AsyncSequence), không selector/Combine.

### 5. Feature model (T26–T28)

Theo quy tắc chung: mỗi model **tự lấy dữ liệu** từ `runtime` bằng ID được truyền vào, tự lắng nghe
`scheduler.updates`/`lock.states()` mà nó cần; view chỉ truyền ID. Hàm map thuần (badge, chuỗi trạng
thái, hành động chính) là hàm tự do, không phải model.

```swift
enum PrimaryAction: Equatable { case none, reauth, grantMore(GrantMorePlan), retry, fixClient(OAuthClientID), openDetails }
func primaryAction(for account: Account, latest: HealthCheckResult?) -> PrimaryAction   // thuần
enum MenuBarBadge: Equatable { case none, yellow, gray, orange, red
    static func from(_ statuses: [AccountStatus]) -> MenuBarBadge }                      // thuần

@MainActor @Observable final class AccountsModel {
    init(runtime: VaultRuntime)
    private(set) var rows: [AccountRow]; private(set) var error: String?
    func load() async; func add(provider: ProviderID, client: OAuthClientID) async
    func perform(_ action: PrimaryAction, on: AccountID) async
}
@MainActor @Observable final class AccountDetailModel { init(runtime:, accountId:) ... reduce, revoke, remove }
@MainActor @Observable final class OAuthClientsModel { CRUD; save client secret qua runtime.secrets.create(kind: .clientSecret) }
@MainActor @Observable final class SecretsModel { requires lock unlocked; reveal(id) -> String (giữ tối đa 30 s trong state rồi xóa) }
@MainActor @Observable final class HealthHistoryModel { init(runtime:, accountId:) }
@MainActor @Observable final class AuditModel { query: AuditQuery }
```

Notifier: chỉ khi status chuyển **sang** `needsReauth`; key dedupe `accountId` + 24 h (lưu
`UserDefaults`). Action "Đăng nhập lại" → `AccountsModel.perform(.reauth, ...)`.

## Implementation Steps

1. **T25 (GLM-5.3)** — §1 (khung), §2, §3, §4, `Platform/*`, `KeyloftApp.swift` với sidebar rỗng,
   `make app`. Xong khi app chạy, menu bar hiện, thêm account Google thật được qua một nút debug tạm.
2. **T26 (Flash)** — MenuBar + Accounts (+ AddAccountFlow, AccountDetail, Notifier wiring). U1–U8.
3. **T27 (Flash)** — Providers/OAuth Clients. U9–U11.
4. **T28 (Flash)** — Secrets (UnlockGate), Health, Audit. U12–U16.

T26–T28 song song sau T25 (khác thư mục Features). `KeyloftApp.swift` sidebar: T25 tạo sẵn 5 mục
trỏ tới `PlaceholderView`; mỗi task chỉ thay đúng dòng của mình.

## Testing

See ./TESTING.md. Model test dùng `VaultRuntime(RuntimeDependencies(...fake...))`.

## Risks and Rollback

- Ký sai → `missingEntitlement` khi chạy; T25 phải ghi lại chính xác bước ký trong report.

## Open Questions

- Không có.
