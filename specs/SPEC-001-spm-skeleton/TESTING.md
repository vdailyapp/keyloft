# SPEC-001: Khung SPM, CI và hạ tầng test — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

Chỉ kiểm tra khung build/test/lint. Logic nghiệp vụ thuộc spec khác.

## Test Environment

macOS 14+, Xcode 16+, `swift test`. Không mạng, không Keychain.

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Smoke mỗi target | `<Target>Tests/SmokeTests` | `import <Target>` biên dịch, `#expect(true)` |
| U2 | Import cấm bị bắt | `scripts/check-imports.sh` | Tạo tạm file `Sources/SecretVault/Bad.swift` có `import TokenVault` → script exit 1, in đường dẫn; xóa file → exit 0 |

## Integration Tests

| # | Scenario | Setup | Expected |
|---|----------|-------|----------|
| I1 | CI trên PR | Push nhánh | Job `ci` xanh, có 3 bước build/lint/test |

## Edge Cases and Failure Modes

- File sai format → `make lint` exit ≠ 0, in tên file.

## Manual Verification

1. `git clean -xfd && make build && make test && make lint` → cả 3 xanh.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| Build xanh Swift 6, warnings-as-errors | I1 |
| Test xanh, ≥1 test/target, < 60 s | U1, Manual 1 |
| Đồ thị dependency khớp TECH.md | U2 + review |
| CI chạy trên PR < 10 phút | I1 |

## Regression Risk

Không có (repo mới).

## Out of Scope

Test nghiệp vụ.
