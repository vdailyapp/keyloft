# T17: Providers: Google, Microsoft, Dropbox + ProviderCatalog

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-007](../../specs/SPEC-007-providers/) | 3 | T03 |

Branch: `task/T17-provider-catalog` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-007 PRODUCT.md
- SPEC-007 TECH §2
- SPEC-007 TESTING U1–U4

## Files (chỉ được tạo/sửa các file này)

- `Sources/Providers/Google.swift`
- `Sources/Providers/Microsoft.swift`
- `Sources/Providers/Dropbox.swift`
- `Sources/Providers/ProviderCatalog.swift`
- `Tests/ProvidersTests/ProviderCatalogTests.swift`

## Deliverables

1. `extension Provider { static let google, microsoft, dropbox }` đúng bảng TECH §2.
2. `actor ProviderCatalog: ProviderRegistry` (chưa nối discovery: tham số `discovery` có thể nil; `refreshDiscovery()` để trống có TODO trỏ T18).

## Tests

SPEC-007 U1–U4.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter ProvidersTests
```

## Lưu ý

- Chép giá trị từ bảng, không tự 'sửa'. Nghi ngờ giá trị sai → ghi Blocked/Follow-up, không đổi.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T17.md` đã viết, BOARD status = `review`
