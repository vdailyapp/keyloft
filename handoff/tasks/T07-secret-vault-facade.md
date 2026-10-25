# T07: SecretVault: protocol SecretStore, facade, InMemorySecretStore

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-004](../../specs/SPEC-004-secret-vault/) | 3 | T03 |

Branch: `task/T07-secret-vault-facade` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-004 PRODUCT.md §Behavior
- SPEC-004 TECH §2, §3
- SPEC-004 TESTING U1–U9

## Files (chỉ được tạo/sửa các file này)

- `Sources/SecretVault/SecretStore.swift`
- `Sources/SecretVault/SecretVault.swift`
- `Tests/KeyloftTestSupport/InMemorySecretStore.swift`
- `Tests/SecretVaultTests/SecretVaultTests.swift`

## Deliverables

1. `SecretAccessPolicy`, `SecretStore`, `SecretStoreError` (TECH §2).
2. `actor SecretVault` + `SecretVaultError` đúng TECH §3 (luồng create/read/rotate/delete/exists/list, bồi hoàn khi metadata lỗi, audit theo actor).
3. `InMemorySecretStore` (actor; `presenceGranted`, `getCount`, `failNextSet: SecretStoreError?`).

## Tests

SPEC-004 U1–U9.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter SecretVaultTests
```

## Lưu ý

- `try?` duy nhất cho phép: bước bồi hoàn xóa Keychain khi metadata insert lỗi (comment lý do).
- Policy: `requiresUserPresence ? .userPresence : .afterFirstUnlock`.
- Không import LocalAuthentication ở task này.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T07.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
