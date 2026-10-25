# T23: VaultRuntime: composition root + test tích hợp GRDB

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-010](../../specs/SPEC-010-cli-runtime/) | 8 | T05, T06, T09, T18, T21, T22 |

Branch: `task/T23-vault-runtime` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-010 PRODUCT.md
- SPEC-010 TECH §1
- SPEC-010 TESTING I1–I3, U13
- init của mọi service (đọc code thật)

## Files (chỉ được tạo/sửa các file này)

- `Sources/VaultRuntime/RuntimeConfiguration.swift`
- `Sources/VaultRuntime/VaultRuntime.swift`
- `Sources/VaultRuntime/UnavailableBrowserSession.swift`
- `Sources/VaultRuntime/RuntimeError.swift`
- `Tests/VaultRuntimeTests/RuntimeIntegrationTests.swift`

## Deliverables

1. `RuntimeContext`, `RuntimeConfiguration.default(for:environment:)`, `RuntimeDependencies`, `VaultRuntime.init(_:policy:)`, `.live(context:browser:)`, `RuntimeError` (`vaultNotInitialized`, `keychainUnavailable(hint:)`).
2. Thứ tự dựng đúng TECH §1; `onCredentialIssued` seed `TokenProvider`.

## Tests

SPEC-010 I1, I2, I3, U13 (+ SPEC-008 I1 chính là I2).

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter VaultRuntimeTests
make test
```

## Lưu ý

- Nếu init của service thật khác TECH: theo code thật, ghi Deviations.
- I3 là test quan trọng nhất của giai đoạn 1 — bắt lỗi FK mà InMemory không bắt.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T23.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
