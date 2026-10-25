# T24: KeyloftCLI: accounts, health, token

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-010](../../specs/SPEC-010-cli-runtime/) | 9 | T23 |

Branch: `task/T24-cli` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-010 PRODUCT.md
- SPEC-010 TECH §2
- SPEC-010 TESTING U1–U12

## Files (chỉ được tạo/sửa các file này)

- `Sources/KeyloftCLI/*.swift`
- `Tests/KeyloftCLITests/*.swift`

## Deliverables

1. 3 subcommand, `AccountSelector`, `Output` (table/JSON, `StandardStreams`), `KeyloftExitCode`, `Keyloft.makeRuntime` (seam).

## Tests

SPEC-010 U1–U12.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter KeyloftCLITests
swift run keyloft --help
```

## Lưu ý

- Thoát với code: `throw ExitCode(rawValue)` của ArgumentParser.
- stdout của `token` chỉ có token + newline; mọi thứ khác ra stderr.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T24.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
