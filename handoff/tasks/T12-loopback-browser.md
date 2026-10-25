# T12: TokenVault: LoopbackServer (NWListener) + BrowserSession + fakes

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-005](../../specs/SPEC-005-oauth-login/) | 2 | T02 |

Branch: `task/T12-loopback-browser` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-005 PRODUCT.md
- SPEC-005 TECH §4
- SPEC-005 TESTING U12–U16, I1
- RFC 8252 §7.3, §8.3

## Files (chỉ được tạo/sửa các file này)

- `Sources/TokenVault/Loopback/CallbackReceiver.swift`
- `Sources/TokenVault/Loopback/LoopbackServer.swift`
- `Sources/TokenVault/Loopback/HTTPRequestParser.swift`
- `Sources/TokenVault/BrowserSession.swift`
- `Tests/KeyloftTestSupport/FakeBrowserSession.swift`
- `Tests/KeyloftTestSupport/FakeCallbackReceiver.swift`
- `Tests/TokenVaultTests/LoopbackServerTests.swift`

## Deliverables

1. Mọi type ở TECH §4. `LoopbackServer` chỉ bind 127.0.0.1, 1 callback hợp lệ duy nhất, 404/405/400 rồi tiếp tục chờ, 302 về `app.vdaily.keyloft://oauth-complete`, timeout/stop.
2. `HTTPRequestParser` thuần (parse request line + query, giới hạn 8 KB) — test riêng.
3. `FakeBrowserSession` (redirect thật bằng URLSession tới loopback / cancel / error), `FakeCallbackReceiver`.

## Tests

SPEC-005 U12–U16, I1.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter TokenVaultTests/Loopback
```

## Lưu ý

- NWListener + DispatchQueue serial private được phép ở file này (AGENTS.md ngoại lệ) — comment.
- Đảm bảo continuation chỉ resume đúng 1 lần (timeout, stop, callback chạy đua).
- Liệt kê trong report: hành vi khi cổng cố định đã bị chiếm (`bindFailed`).
- Hủy từ trình duyệt: throw `BrowserSessionError.userCancelled` (định nghĩa trong `BrowserSession.swift`, T12 chạy trước khi có `OAuthError`).

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T12.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
