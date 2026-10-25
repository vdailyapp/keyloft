# T15: TokenVault: OAuthLoginService (điều phối đăng nhập)

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-005](../../specs/SPEC-005-oauth-login/) | 5 | T07, T10, T11, T12, T13, T14 |

Branch: `task/T15-oauth-login-service` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-005 toàn bộ
- SPEC-004 TECH §3
- code thật của T07, T10–T14

## Files (chỉ được tạo/sửa các file này)

- `Sources/TokenVault/OAuthLoginService.swift`
- `Tests/TokenVaultTests/OAuthLoginServiceTests.swift`
- `Tests/TokenVaultTests/LoginIntegrationTests.swift`

## Deliverables

1. `LoginTarget`, `LoginRequest`, `LoginOutcome`, `CredentialIssuedObserver`, `actor OAuthLoginService` theo đúng 16 bước TECH §7, gồm bồi hoàn secret.
2. Map `BrowserSessionError.userCancelled` → `OAuthError.userCancelled`, `LoopbackError.timeout` → `.timeout`, `.cancelled` → `.userCancelled`.

## Tests

SPEC-005 U33–U45, I2 (+ edge case 2 login song song).

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter TokenVaultTests
```

## Lưu ý

- Task group chạy đua browser/receiver: browser trả về bình thường KHÔNG được kết thúc nhóm (U43).
- `receiver.stop()` phải được gọi trên mọi đường thoát (thành công, lỗi, hủy).
- Không gọi token endpoint trước khi kiểm state + iss (U34, U35).

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T15.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
