# T11: TokenVault: AuthorizationRequest + ScopeNormalizer

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-005](../../specs/SPEC-005-oauth-login/) | 4 | T10 |

Branch: `task/T11-authorize-url-scopes` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-005 TECH §3
- SPEC-005 TESTING U6–U11
- SPEC-002 TECH §5 (ProviderQuirks)

## Files (chỉ được tạo/sửa các file này)

- `Sources/TokenVault/AuthorizationRequest.swift`
- `Sources/TokenVault/ScopeNormalizer.swift`
- `Tests/TokenVaultTests/AuthorizationRequestTests.swift`
- `Tests/TokenVaultTests/ScopeNormalizerTests.swift`

## Deliverables

1. `AuthorizationRequest.url()` thứ tự tham số cố định, RFC 3986 encode, chặn ghi đè tham số bảo mật.
2. `ScopeNormalizer.granted/canonical`.

## Tests

SPEC-005 U6–U11.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter TokenVaultTests
```

## Lưu ý

- Không dùng `URLComponents.queryItems` để encode (nó không encode `+`, `/`, `:` như mong muốn) — tự encode bằng bộ ký tự unreserved RFC 3986.
- U6: viết chuỗi kỳ vọng đầy đủ trong test.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T11.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
