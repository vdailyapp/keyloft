# SPEC-004: SecretVault — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

Keychain API là C (SecItem*), `LAContext` không `Sendable`, và Data Protection Keychain cần app
đã ký + entitlement nên không chạy được trong `swift test` thường. Thiết kế phải cô lập phần đó sau
một protocol để mọi logic khác test được bằng fake.

## Relevant Code

- `Sources/VaultDomain/Secret.swift` — `Secret`, `KeychainRef`, `SecretKind`
- `Sources/VaultDomain/Repositories.swift` — `SecretMetadataRepository`, `AuditLog`

## Current State

Placeholder `Sources/SecretVault/SecretVault.swift`.

## Proposed Changes

### 1. File layout

```
Sources/SecretVault/
├── SecretStore.swift            # protocol + SecretAccessPolicy + SecretStoreError
├── SecretVault.swift            # actor facade (T07)
├── KeychainSecretStore.swift    # SecItem impl (T08)
├── KeychainQuery.swift          # build dictionary, map OSStatus (T08)
└── VaultLock.swift              # LAContext gate (T09)
Tests/KeyloftTestSupport/InMemorySecretStore.swift   # (T07)
```

### 2. SecretStore

```swift
public enum SecretAccessPolicy: Sendable, Equatable {
    case afterFirstUnlock      // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    case userPresence          // SecAccessControl(kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence)
}

public protocol SecretStore: Sendable {
    /// Ghi đè nếu đã có (delete + add, vì access control không update được).
    func set(_ data: Data, for ref: KeychainRef, policy: SecretAccessPolicy) async throws
    /// `reason` hiện trong hộp thoại Touch ID nếu item cần presence.
    func get(_ ref: KeychainRef, reason: String) async throws -> Data
    func delete(_ ref: KeychainRef) async throws           // không có → không lỗi
    /// Không bao giờ hiện UI xác thực.
    func contains(_ ref: KeychainRef) async throws -> Bool
}

public enum SecretStoreError: Error, Sendable, Equatable {
    case notFound
    case userCanceled          // errSecUserCanceled (-128)
    case authFailed            // errSecAuthFailed
    case interactionNotAllowed // errSecInteractionNotAllowed: Vault khóa / máy khóa
    case missingEntitlement    // errSecMissingEntitlement (-34018): build chưa ký
    case osStatus(Int32)
}
```

### 3. SecretVault facade (T07)

```swift
public enum SecretVaultError: Error, Sendable, Equatable {
    case notFound(SecretID)
    case store(SecretStoreError)
    case metadata(String)
}

public actor SecretVault {
    public init(store: any SecretStore, metadata: any SecretMetadataRepository,
                audit: any AuditLog, clock: any DateProvider, ids: any IDGenerator)

    public static func defaultRequiresUserPresence(_ kind: SecretKind) -> Bool   // bảng ở PRODUCT §Behavior 2

    public func create(kind: SecretKind, label: String, value: Data,
                       requiresUserPresence: Bool? = nil, actor: AuditActor) async throws -> Secret
    public func read(_ id: SecretID, reason: String, actor: AuditActor) async throws -> Data
    public func rotate(_ id: SecretID, to value: Data, actor: AuditActor) async throws -> Secret
    public func delete(_ id: SecretID, actor: AuditActor) async throws
    public func exists(_ id: SecretID) async throws -> Bool     // metadata có && store.contains
    public func list(kind: SecretKind?) async throws -> [Secret]
}
```

Luồng:

- `create`: id = `SecretID(rawValue: ids.make())`, ref = `KeychainRef(kind:id:)` →
  `store.set` → `metadata.insert`; nếu insert throw → `try? await store.delete(ref)` (đây là chỗ
  duy nhất cho phép `try?`, có comment) rồi rethrow `.metadata`. Audit `secretCreated`
  target `"secret:<id>"`.
- `read`: metadata không có → `.notFound`. Audit `secretRead` khi `actor != .app`.
- `rotate`: `store.set` cùng ref, cùng policy → `metadata.markRotated(at: clock.now())`.
  Audit `secretRotated`. Trả `Secret` đã cập nhật.
- `delete`: `store.delete` → `metadata.delete`. Audit `secretDeleted`.
- Mọi `SecretStoreError` bọc thành `.store(...)`.
- Ghi audit lỗi → throw (audit là yêu cầu bảo mật, không được im lặng bỏ qua). Thao tác Keychain
  đã xong thì giữ nguyên, không rollback.

`InMemorySecretStore` (TestSupport): actor, dict `[KeychainRef: (Data, SecretAccessPolicy)]`, có
`var presenceGranted = true` để giả lập Touch ID; `get` item `.userPresence` khi
`presenceGranted == false` → `.userCanceled`. Đếm `getCount` để test.

### 4. KeychainSecretStore (T08)

```swift
public struct KeychainConfiguration: Sendable {
    public var service: String = KeychainRef.service
    public var accessGroup: String?               // "<TEAMID>.app.vdaily.keyloft" khi app đã ký
    public var useDataProtectionKeychain: Bool    // true cho app ký; false cho dev/CLI chưa ký
}
/// Tách khỏi VaultLock để T08 không phụ thuộc T09; VaultLock conform (T09).
public protocol KeychainAuthContextProvider: Sendable { func currentContext() async -> LAContext? }

public actor KeychainSecretStore: SecretStore {
    public init(configuration: KeychainConfiguration, contextProvider: (any KeychainAuthContextProvider)?)
}
```

Query cơ sở: `kSecClass: kSecClassGenericPassword`, `kSecAttrService`, `kSecAttrAccount: ref.account`,
`kSecAttrSynchronizable: false`, `kSecUseDataProtectionKeychain` (theo config), `kSecAttrAccessGroup`
(nếu có).

- `set`: `SecItemDelete` (bỏ qua notFound) → `SecItemAdd` với `kSecValueData` và
  - `.afterFirstUnlock`: `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  - `.userPresence`: `kSecAttrAccessControl: SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &err)`
- `get`: `kSecReturnData: true`, `kSecMatchLimit: kSecMatchLimitOne`. Nếu `contextProvider` trả context đang mở
  → `kSecUseAuthenticationContext: context`; luôn đặt `kSecUseOperationPrompt` = `reason`
  (hoặc `context.localizedReason`).
- `contains`: `kSecReturnAttributes: true` (không trả data), `kSecUseAuthenticationContext` = một
  `LAContext` mới với `interactionNotAllowed = true`. `errSecSuccess` hoặc
  `errSecInteractionNotAllowed` → `true`; `errSecItemNotFound` → `false`.
- Gọi `SecItem*` trong actor (blocking ngắn, chấp nhận được; `get` có thể chờ Touch ID — chạy
  trong `Task.detached` không cần: actor riêng, không chặn MainActor).
- Map `OSStatus` → `SecretStoreError` trong `KeychainQuery.swift` (`static func map(_ status: OSStatus) -> SecretStoreError`).

### 5. VaultLock (T09)

```swift
public enum VaultLockState: Sendable, Equatable { case locked, unlocked(until: Date) }

public protocol UserPresenceAuthenticator: Sendable {
    /// Hiện Touch ID / mật khẩu. Trả context đã xác thực, hoặc throw userCanceled/authFailed.
    func authenticate(reason: String) async throws -> AuthenticatedContext
}
/// Bọc LAContext để vượt ranh giới actor; chỉ VaultLock và KeychainSecretStore chạm vào `context`.
public final class AuthenticatedContext: @unchecked Sendable { let context: LAContext }   // ngoại lệ có comment

public actor VaultLock {
    public static let reuseDuration: TimeInterval = 300   // = LATouchIDAuthenticationMaximumAllowableReuseDuration
    public init(authenticator: any UserPresenceAuthenticator, clock: any DateProvider)
    public var state: VaultLockState { get }               // tự chuyển locked khi quá hạn
    public func unlock(reason: String) async throws
    public func lock()
    public func noteActivity()                             // gia hạn idle timer (≤ reuseDuration)
    public func currentContext() -> LAContext?             // KeychainAuthContextProvider; nil nếu locked/quá hạn
    public func states() -> AsyncStream<VaultLockState>    // cho UI
}
public struct LocalAuthenticationAuthenticator: UserPresenceAuthenticator   // LAContext.evaluatePolicy(.deviceOwnerAuthentication)
```

`LAContext.touchIDAuthenticationAllowableReuseDuration = 300`. Sự kiện ngủ/khóa màn hình do App
gọi `lock()` (SPEC-011), `VaultLock` không import AppKit.

## Implementation Steps

1. **T07 (Flash)** — `SecretStore.swift`, `SecretVault.swift`, `InMemorySecretStore`. U1–U9.
2. **T08 (GLM-5.3)** — `KeychainSecretStore`, `KeychainQuery`. U10, I1–I4 (gated).
3. **T09 (GLM-5.3)** — `VaultLock`, `LocalAuthenticationAuthenticator`, nối `lock` vào
   `KeychainSecretStore.get`. U11–U14.

## Testing

See ./TESTING.md. Seam: `UserPresenceAuthenticator` để test `VaultLock` không cần Touch ID thật;
test Keychain thật cần `KEYLOFT_KEYCHAIN_TESTS=1` và chạy với
`useDataProtectionKeychain: false` (login keychain, không cần entitlement).

## Risks and Rollback

- Data Protection Keychain + access group sai team → `missingEntitlement` lúc runtime. Runtime
  phát hiện lần đầu và báo lỗi rõ (SPEC-010).

## Open Questions

- macOS login keychain (file-based) có thể hiện hộp thoại "allow access" khi binary đổi chữ ký
  (dev build). Chấp nhận cho dev; bản phát hành dùng Data Protection Keychain.
