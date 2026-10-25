# T27: App: OAuth Clients (Providers)

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-011](../../specs/SPEC-011-macos-app/) | 10 | T25 |

Branch: `task/T27-ui-oauth-clients` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-011 PRODUCT §Behavior 4
- SPEC-011 TECH §5
- SPEC-011 TESTING U9–U11
- SPEC-007 TECH §2

## Files (chỉ được tạo/sửa các file này)

- `App/Features/Providers/*.swift`
- `App/KeyloftApp.swift (chỉ dòng sidebar OAuth Clients)`
- `App/Tests/KeyloftAppTests/OAuthClientsTests.swift`

## Deliverables

1. Danh sách + form tạo/sửa/xóa OAuth client; client secret lưu qua `runtime.secrets.create(kind: .clientSecret, ...)`; link hướng dẫn mỗi provider; nhắc Google In production.

## Tests

SPEC-011 U9–U11.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make app
xcodebuild test -scheme Keyloft
```

## Lưu ý

- SecureField; xóa giá trị secret khỏi state ngay sau khi lưu.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T27.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
