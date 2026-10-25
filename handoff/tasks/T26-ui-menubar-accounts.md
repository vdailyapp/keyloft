# T26: App: Menu bar + Accounts + notification

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-011](../../specs/SPEC-011-macos-app/) | 10 | T25 |

Branch: `task/T26-ui-menubar-accounts` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-011 PRODUCT §Behavior 1, 3, 8
- SPEC-011 TECH §5
- SPEC-011 TESTING U1–U8
- SPEC-009 TECH §2

## Files (chỉ được tạo/sửa các file này)

- `App/Features/MenuBar/*.swift`
- `App/Features/Accounts/*.swift`
- `App/KeyloftApp.swift (chỉ dòng sidebar Accounts + MenuBarExtra content)`
- `App/Tests/KeyloftAppTests/{MenuBar,Accounts}Tests.swift`

## Deliverables

1. `MenuBarBadge`, `primaryAction`, `MenuBarView/Model`, `AccountsView/Model`, `AccountDetailView/Model`, `AddAccountFlow`; nối `Notifier` action "Đăng nhập lại".

## Tests

SPEC-011 U1–U8.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make app
xcodebuild test -scheme Keyloft
```

## Lưu ý

- Model tự lấy dữ liệu từ `runtime` bằng ID; View không truyền dữ liệu account xuống model con.
- Mọi hành động account đi qua `runtime.scopes` (ScopeService).
- Xóa nút debug của T25.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T26.md` đã viết, BOARD status = `review`
