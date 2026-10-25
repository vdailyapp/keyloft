# SPEC-004: SecretVault — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

`SecretVault` facade, `KeychainSecretStore`, `VaultLock`. UI khóa/mở khóa thuộc SPEC-011.

## Test Environment

- Unit: `swift test --filter SecretVaultTests` — `InMemorySecretStore`, `InMemorySecretMetadataRepository`,
  `InMemoryAuditLog`, `FixedDateProvider`, `SequentialIDGenerator`, `FakeAuthenticator` (viết trong test).
- Keychain thật: `make test-keychain` (`KEYLOFT_KEYCHAIN_TESTS=1`), service test
  `app.vdaily.keyloft.tests.<uuid>` để không đụng dữ liệu thật; dọn sạch trong `deinit`/cuối test.

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Store lỗi khi create | `SecretVault.create`, store throw `.osStatus(-1)` | throw `.store(.osStatus(-1))`; metadata rỗng; không audit `secretCreated` |
| U2 | Create thành công | `create(kind: .refreshToken ...)` | store có item theo `KeychainRef(kind:id:)`, metadata có, `requiresUserPresence == false`, audit 1 event |
| U3 | Metadata lỗi → bồi hoàn | metadata repo fake throw khi insert | throw `.metadata`; store không còn item |
| U4 | Mặc định presence theo kind | `defaultRequiresUserPresence` 4 kind | refreshToken/clientSecret false; apiKey/password true |
| U5 | Read id không tồn tại | `read` | `.notFound(id)` |
| U6 | Read bị hủy Touch ID | `presenceGranted = false`, secret apiKey | `.store(.userCanceled)`; không audit `secretRead` thành công |
| U7 | Rotate | `rotate` | store giữ giá trị mới, `rotatedAt == clock.now()`, cùng ref, audit `secretRotated` |
| U8 | Không lộ giá trị | create với value `"rt-SECRET-123"`, ép lỗi ở mọi bước | `String(describing:)` của mọi error, audit event, `Secret` không chứa `rt-SECRET-123` |
| U9 | Audit theo actor | read với `.app` rồi `.cli` | chỉ 1 event `secretRead` (actor cli) |
| U10 | Map OSStatus | `KeychainQuery.map` | -25300→notFound, -128→userCanceled, -25293→authFailed, -25308→interactionNotAllowed, -34018→missingEntitlement, khác→osStatus |
| U11 | Unlock thành công | `VaultLock.unlock`, clock t0 | `state == .unlocked(until: t0+300)` |
| U12 | Hết hạn tự khóa | advance 301 s | `state == .locked`, `currentContext() == nil` |
| U13 | Unlock bị hủy | authenticator throw userCanceled | state vẫn `.locked`, lỗi truyền ra |
| U14 | `lock()` thủ công + stream | subscribe `states()`, unlock, lock | nhận `[.locked, .unlocked, .locked]` |

## Integration Tests (gated `KEYLOFT_KEYCHAIN_TESTS=1`)

| # | Scenario | Setup | Expected |
|---|----------|-------|----------|
| I1 | Thuộc tính item | `set` `.afterFirstUnlock` rồi đọc attributes bằng `SecItemCopyMatching` | item tồn tại đúng class/account. *(Cập nhật T08: login keychain không trả về thuộc tính accessible/synchronizable — giá trị hai thuộc tính này được bảo đảm bởi cấu trúc query lúc ADD, kiểm bằng unit test `KeychainQueryTests.baseQuery`, và chỉ đọc lại được trong Data Protection Keychain của app đã ký)* |
| I2 | Set/get/overwrite/delete | set "a", set "b", get, delete, get | get → "b"; sau delete → `.notFound`; delete lần 2 không lỗi |
| I3 | contains không UI | set `.userPresence` | `contains == true`, test không treo (timeout 5 s). *(Cập nhật T08: item SecAccessControl cần Data Protection Keychain — binary chưa ký bị `-34018`; test tự tắt theo probe năng lực, chạy đầy đủ trong app đã ký ở SPEC-011/T29)* |
| I4 | get item presence không context, không tương tác | `get` với `LAContext.interactionNotAllowed` (qua `KeychainAuthContextProvider`) | `.interactionNotAllowed`. *(Cùng ràng buộc DP keychain như I3)* |

## Edge Cases and Failure Modes

- `delete` item không tồn tại → không throw.
- Label rỗng → cho phép (UI tự validate).
- Value rỗng `Data()` → tầng vault cho phép lưu; UI (SPEC-011) chặn nhập rỗng.

## Manual Verification

1. App đã ký: Secrets → thêm API key (presence on) → bấm "Hiện" → Touch ID xuất hiện với tên key.
2. Trong 5 phút bấm "Hiện" key khác → không hỏi lại. Khóa màn hình, mở lại, bấm → hỏi lại.
3. `security find-generic-password -s app.vdaily.keyloft` → thấy item, `-w` hỏi quyền / thất bại.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| Không lộ giá trị | U8 |
| Không sync, ThisDeviceOnly | I1 |
| Item presence cần Touch ID | U6, I4, Manual 1 |
| `exists` không UI | I3 |
| Không item mồ côi | U3 |

## Regression Risk

Đổi format `KeychainRef.account` → không tìm thấy item cũ. U11 SPEC-002 khóa format.

## Out of Scope

Secure Enclave, sharing qua access group giữa app & CLI (kiểm thủ công ở SPEC-011).
