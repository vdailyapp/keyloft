# T28: App: Secrets (Touch ID), Health history, Audit

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-011](../../specs/SPEC-011-macos-app/) | 10 | T25 |

Branch: `task/T28-ui-secrets-health-audit` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-011 PRODUCT §Behavior 5–7
- SPEC-011 TECH §5
- SPEC-011 TESTING U12–U16
- SPEC-004 TECH §5

## Files (chỉ được tạo/sửa các file này)

- `App/Features/Secrets/*.swift`
- `App/Features/Health/*.swift`
- `App/Features/Audit/*.swift`
- `App/KeyloftApp.swift (chỉ 3 dòng sidebar tương ứng)`
- `App/Tests/KeyloftAppTests/{Secrets,Health,Audit}Tests.swift`

## Deliverables

1. `UnlockGate`, `SecretsView/Model` (reveal tự xóa 30 s, copy qua `Clipboard`), `HealthHistoryView/Model`, `AuditView/Model`.

## Tests

SPEC-011 U12–U16.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make app
xcodebuild test -scheme Keyloft
```

## Lưu ý

- Refresh token: chỉ metadata, không nút Hiện.
- Secrets model lắng nghe `runtime.lock.states()`; locked → xóa rows.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T28.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
