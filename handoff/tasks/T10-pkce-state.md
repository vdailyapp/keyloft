# T10: TokenVault: Base64URL, PKCE, state

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-005](../../specs/SPEC-005-oauth-login/) | 3 | T03 |

Branch: `task/T10-pkce-state` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-005 TECH §2
- SPEC-005 TESTING U1–U5

## Files (chỉ được tạo/sửa các file này)

- `Sources/TokenVault/Base64URL.swift`
- `Sources/TokenVault/PKCE.swift`
- `Tests/TokenVaultTests/PKCETests.swift`

## Deliverables

1. `Base64URL`, `PKCEPair` (generate + init(verifier:) validate), `OAuthState.generate`, `constantTimeEquals` (TECH §2).

## Tests

SPEC-005 U1–U5.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter TokenVaultTests/PKCE
```

## Lưu ý

- SHA256 qua `CryptoKit`.
- `constantTimeEquals`: so độ dài trước được, nhưng vòng lặp so byte không được dừng sớm.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T10.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
