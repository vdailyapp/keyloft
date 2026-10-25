# T01: Khung SPM, Makefile, lint, CI

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-001](../../specs/SPEC-001-spm-skeleton/) | 0 | — |

Branch: `task/T01-spm-skeleton` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-001 TECH.md toàn bộ

## Files (chỉ được tạo/sửa các file này)

- `Package.swift`
- `Makefile`
- `.swift-format`
- `.gitignore`
- `.github/workflows/ci.yml`
- `scripts/check-imports.sh`
- `Sources/*/<Target>.swift (placeholder)`
- `Sources/KeyloftCLI/Keyloft.swift`
- `Tests/*/SmokeTests.swift`
- `Tests/KeyloftTestSupport/KeyloftTestSupport.swift`
- `Tests/ProvidersTests/Fixtures/.gitkeep`
- `README.md (5 dòng: build/test)`

## Deliverables

1. `Package.swift` đúng nguyên văn TECH §2 (gồm product `KeyloftTestSupport`, test target `KeyloftCLITests`).
2. Mỗi target có 1 file placeholder `public enum <Target> { public static let version = "0.1.0" }` (CLI: `@main struct Keyloft: AsyncParsableCommand` có `--version`).
3. `Makefile` các target `build test test-keychain lint format` (TECH §3).
4. `scripts/check-imports.sh` theo TECH §4 + quy tắc SPEC-002 (cho phép `import Security` chỉ ở `Sources/VaultDomain/Infrastructure.swift`). `chmod +x`.
5. `.swift-format`: `lineLength: 120`, indent 4 space.
6. CI `macos-14`, Xcode 16.x, build với `-Xswiftc -warnings-as-errors`, lint, test.

## Tests

SPEC-001 U1, U2 (U2 viết thành script `scripts/test-check-imports.sh`, gọi trong CI).

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
make test
./scripts/test-check-imports.sh
```

## Lưu ý

- Không thêm target giai đoạn 2–4.
- GRDB `from: "7.0.0"`; nếu resolve lỗi, pin bản 7.x mới nhất và ghi vào report.
- `.gitignore`: `.build/`, `*.xcodeproj`, `App/Local.xcconfig`, `.swiftpm/`, `DerivedData/`.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T01.md` đã viết, BOARD status = `review`
