# T19: Providers: API probe Google/Microsoft/Dropbox

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-007](../../specs/SPEC-007-providers/) | 4 | T17 |

Branch: `task/T19-api-probes` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-007 PRODUCT §Behavior 3–4
- SPEC-007 TECH §4
- SPEC-007 TESTING U10–U19

## Files (chỉ được tạo/sửa các file này)

- `Sources/Providers/APIProbe.swift`
- `Sources/Providers/GoogleDriveProbe.swift`
- `Sources/Providers/MicrosoftGraphProbe.swift`
- `Sources/Providers/DropboxProbe.swift`
- `Tests/ProvidersTests/Fixtures/*-{about,drive,space-usage,403,401}*.json`
- `Tests/ProvidersTests/ProbeTests.swift`
- `scripts/check-imports.sh (thêm luật grep `\.google|\.microsoft|\.dropbox` trong TokenVault/HealthCheck)`

## Deliverables

1. `Quota`, `ProbeResult`, `ProbeError` + `isTransient`, `APIProbe`, `ProbeFactory`, 3 probe.

## Tests

SPEC-007 U10–U19.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter ProvidersTests
```

## Lưu ý

- Google quota là chuỗi số → `Int64(string)`.
- Dropbox: POST không body, không Content-Type.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T19.md` đã viết, BOARD status = `review`
