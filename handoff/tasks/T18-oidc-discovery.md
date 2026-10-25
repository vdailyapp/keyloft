# T18: Providers: OIDC Discovery + merge an toàn

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-007](../../specs/SPEC-007-providers/) | 4 | T17 |

Branch: `task/T18-oidc-discovery` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-007 TECH §3
- SPEC-007 TESTING U5–U9

## Files (chỉ được tạo/sửa các file này)

- `Sources/Providers/OIDCDiscovery.swift`
- `Sources/Providers/ProviderCatalog.swift (chỉ refreshDiscovery + áp cache)`
- `Tests/ProvidersTests/Fixtures/{google,microsoft,dropbox}-discovery.json`
- `Tests/ProvidersTests/DiscoveryTests.swift`

## Deliverables

1. `DiscoveryDocument`, `OIDCDiscovery.fetch/merge`; `ProviderCatalog.refreshDiscovery()` tải 3 provider, lỗi giữ tĩnh.

## Tests

SPEC-007 U5–U9.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter ProvidersTests
```

## Lưu ý

- Fixture: tải bằng `curl` hôm làm task (lưu nguyên văn); nếu không có mạng, viết fixture tối thiểu đúng các field và ghi vào report.
- So sánh fixture với bảng TECH §2 — khác thì ghi Follow-up cho người quyết (không sửa bảng).

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T18.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
