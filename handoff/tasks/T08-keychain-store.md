# T08: SecretVault: KeychainSecretStore (SecItem, access control)

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-004](../../specs/SPEC-004-secret-vault/) | 4 | T07 |

Branch: `task/T08-keychain-store` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-004 toàn bộ

## Files (chỉ được tạo/sửa các file này)

- `Sources/SecretVault/KeychainSecretStore.swift`
- `Sources/SecretVault/KeychainQuery.swift`
- `Tests/SecretVaultTests/KeychainQueryTests.swift`
- `Tests/SecretVaultTests/SecretVaultKeychainTests.swift`

## Deliverables

1. `KeychainConfiguration`, `actor KeychainSecretStore: SecretStore` đúng TECH §4 (set = delete+add, get với operation prompt, contains không UI, map OSStatus).
2. Khai báo `protocol KeychainAuthContextProvider: Sendable { func currentContext() async -> LAContext? }` trong `KeychainSecretStore.swift`; init nhận `contextProvider: (any KeychainAuthContextProvider)?` (T09 cho `VaultLock` conform).

## Tests

SPEC-004 U10 (unit) + I1–I4 (gated `KEYLOFT_KEYCHAIN_TESTS=1`, config `useDataProtectionKeychain: false`, service test riêng, dọn sau test).

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter SecretVaultTests
make test-keychain
```

## Lưu ý

- Chạy `make test-keychain` trên máy thật và dán kết quả vào report; CI không chạy.
- Chú ý `LAContext` không Sendable: tạo và dùng trong cùng actor; không trả ra ngoài.
- Nêu trong report: hành vi khi item cần presence mà gọi `get` lúc máy khóa.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T08.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
