# T13: TokenVault: TokenEndpointClient, OAuthError, form encoding

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-005](../../specs/SPEC-005-oauth-login/) | 3 | T03 |

Branch: `task/T13-token-endpoint` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-005 TECH §5
- SPEC-005 TESTING U17–U26

## Files (chỉ được tạo/sửa các file này)

- `Sources/TokenVault/OAuthError.swift`
- `Sources/TokenVault/TokenEndpointClient.swift`
- `Sources/TokenVault/FormEncoding.swift`
- `Tests/TokenVaultTests/TokenEndpointClientTests.swift`

## Deliverables

1. `TokenResponse` (description che token), `ClientCredentials`, `TokenEndpointClient` (exchange/refresh/revoke), `OAuthError` + `isTransient`, `FormEncoding.encode`.

## Tests

SPEC-005 U17–U26.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter TokenVaultTests/TokenEndpoint
```

## Lưu ý

- Form encode: unreserved `A-Z a-z 0-9 - . _ *` giữ nguyên, space → `+`, còn lại `%XX` hoa.
- Đọc `error` từ JSON body cả khi HTTP 401 (Google/Microsoft trả 400/401).

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T13.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
