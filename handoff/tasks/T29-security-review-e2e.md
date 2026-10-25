# T29: Review bảo mật (RFC 9700/MASVS) + E2E thủ công 3 provider

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | SPEC-005..011 | 11 | T24, T26, T27, T28 |

Branch: `task/T29-security-review-e2e` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- docs/PROJECT-SPEC.md mục Chuẩn tuân theo
- Mọi PRODUCT.md
- SPEC-011 TESTING Manual 1–10
- SPEC-010 TESTING Manual

## Files (chỉ được tạo/sửa các file này)

- `docs/SECURITY-REVIEW-PHASE1.md`
- `handoff/reports/T29.md`
- (sửa lỗi nhỏ tìm thấy — mỗi lỗi lớn tạo task mới T30+ trong BOARD)

## Deliverables

1. Checklist RFC 9700 (state, PKCE, exact redirect, rotation, không implicit), RFC 8252, RFC 9207, OIDC id_token checks, Keychain attributes, log/description không lộ secret, OWASP MASVS-STORAGE/AUTH/NETWORK — mỗi mục PASS/FAIL + bằng chứng (file:dòng hoặc test ID).
2. Kết quả chạy checklist manual SPEC-011 1–10 + SPEC-010 Manual 1–3 (người thực hiện ký tên).

## Tests

Toàn bộ `make test`, `make test-keychain`, `xcodebuild test`.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
make test
make test-keychain
make app
```

## Lưu ý

- Agent không đăng nhập account thật; người chạy phần manual, agent tổng hợp.
- FAIL nghiêm trọng → tạo task mới trong BOARD, không vá vội trong T29.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T29.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
