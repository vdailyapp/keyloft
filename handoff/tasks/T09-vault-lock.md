# T09: SecretVault: VaultLock + LocalAuthenticationAuthenticator

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-004](../../specs/SPEC-004-secret-vault/) | 5 | T08 |

Branch: `task/T09-vault-lock` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-004 PRODUCT §Behavior 3–5
- SPEC-004 TECH §5
- SPEC-004 TESTING U11–U14
- Sources/SecretVault/KeychainSecretStore.swift

## Files (chỉ được tạo/sửa các file này)

- `Sources/SecretVault/VaultLock.swift`
- `Sources/SecretVault/KeychainSecretStore.swift (chỉ nối context)`
- `Tests/SecretVaultTests/VaultLockTests.swift`

## Deliverables

1. `VaultLockState`, `UserPresenceAuthenticator`, `AuthenticatedContext`, `actor VaultLock`, `LocalAuthenticationAuthenticator` (TECH §5).
2. `VaultLock` conform protocol context provider của T08; `KeychainSecretStore.get` dùng context khi unlocked.
3. `states()` phát trạng thái hiện tại ngay khi subscribe, rồi mỗi lần đổi (kể cả tự hết hạn — dùng clock tiêm, kiểm tra khi truy cập `state`).

## Tests

SPEC-004 U11–U14.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter SecretVaultTests
```

## Lưu ý

- Hết hạn tự động: không cần timer thật ở task này — `state` tính lại theo `clock.now()`; App (T25) gọi `lock()` khi ngủ.
- `AuthenticatedContext` là ngoại lệ `@unchecked Sendable` duy nhất trong Sources/ — comment rõ vì sao an toàn.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T09.md` đã viết, BOARD status = `review`
