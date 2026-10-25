# T14: TokenVault: IDTokenClaims decode + validate

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-005](../../specs/SPEC-005-oauth-login/) | 4 | T10, T13 |

Branch: `task/T14-id-token` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-005 TECH §6
- SPEC-005 TESTING U27–U32

## Files (chỉ được tạo/sửa các file này)

- `Sources/TokenVault/IDToken.swift`
- `Tests/KeyloftTestSupport/TestJWT.swift`
- `Tests/TokenVaultTests/IDTokenTests.swift`

## Deliverables

1. `IDTokenClaims` (aud string|array, NumericDate), `decode`, `validate(provider:clientId:now:leeway:)`, `bestEmail`.
2. `TestJWT.make(header:claims:)` trong TestSupport.

## Tests

SPEC-005 U27–U32.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter TokenVaultTests/IDToken
```

## Lưu ý

- Decode payload bằng `Base64URL.decode` (T10). Lỗi → `OAuthError.invalidIDToken(reason)` (T13).
- Không verify chữ ký; nhưng header `alg` phải khác `none`.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T14.md` đã viết, BOARD status = `review`
