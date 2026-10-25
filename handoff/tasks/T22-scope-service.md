# T22: TokenVault: ScopeService (cấp thêm, thu hẹp, thu hồi, xóa account)

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-009](../../specs/SPEC-009-scope-management/) | 6 | T15, T16 |

Branch: `task/T22-scope-service` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-009 toàn bộ
- SPEC-005 TECH §7
- SPEC-006 TECH §2
- SPEC-004 TECH §3

## Files (chỉ được tạo/sửa các file này)

- `Sources/TokenVault/ScopeService.swift`
- `Sources/TokenVault/LoginRunner.swift`
- `Sources/SecretVault/SecretVault.swift (thêm purgeValue)`
- `Tests/KeyloftTestSupport/FakeLoginRunner.swift`
- `Tests/TokenVaultTests/ScopeServiceTests.swift`
- `Tests/SecretVaultTests/PurgeValueTests.swift`

## Deliverables

1. Mọi type + `actor ScopeService` đúng TECH §2–§3; `SecretVault.purgeValue`.

## Tests

SPEC-009 U1–U14.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter TokenVaultTests
swift test --filter SecretVaultTests
```

## Lưu ý

- Không có `if provider == .google`: mọi rẽ nhánh theo `quirks.incrementalAuth` / `quirks.revocation`.
- Thứ tự xóa trong removeAccount: account (cascade) TRƯỚC, secret SAU (FK RESTRICT).

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T22.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
