# T16: TokenVault: TokenProvider (cache, single-flight, rotation)

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-006](../../specs/SPEC-006-token-refresh-cache/) | 5 | T07, T11, T13 |

Branch: `task/T16-token-provider` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-006 toàn bộ
- SPEC-005 TECH §3, §5
- SPEC-004 TECH §3

## Files (chỉ được tạo/sửa các file này)

- `Sources/TokenVault/TokenProvider.swift`
- `Sources/TokenVault/TokenVaultError.swift`
- `Tests/TokenVaultTests/TokenProviderTests.swift`

## Deliverables

1. `TokenVaultError`, `actor TokenProvider` đúng TECH §2–§4.

## Tests

SPEC-006 U1–U14 + property test transient (seed cố định).

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter TokenVaultTests/TokenProvider
```

## Lưu ý

- Trong report phân tích reentrancy: chỉ ra từng `await` trong actor và vì sao không sinh refresh thứ hai.
- U5 phải tất định: dùng `StubHTTPClient` với continuation/điểm chặn thay vì sleep.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T16.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
