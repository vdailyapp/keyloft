# SPEC-002: VaultDomain — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

Type thuần trong `VaultDomain` và fake trong `KeyloftTestSupport`. Không I/O.

## Test Environment

`swift test --filter VaultDomainTests`. Không cần fixture ngoài.

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Scope chuỗi rỗng / chỉ khoảng trắng | `ScopeSet(spaceDelimited:)` | `isEmpty == true`, `spaceDelimited == ""` |
| U2 | Tách nhiều loại whitespace, bỏ trùng | `ScopeSet(spaceDelimited: " openid\temail  email\n")` | `values == ["openid","email"]` |
| U3 | Phân biệt hoa thường | `ScopeSet(["Files.Read","files.read"])` | count == 2 |
| U4 | `spaceDelimited` ổn định | `["b","a","c"]` | `"a b c"` |
| U5 | `missing(in:)` | cần `[drive, openid, email]`, granted `[openid, email]` | `[drive]`; granted ⊇ cần → rỗng |
| U6 | Codable ScopeSet | encode `["b","a"]` | JSON `["a","b"]`; decode lại bằng nhau |
| U7 | Codable round-trip mọi entity | `Account`, `Credential`, `OAuthClient`, `Secret`, `HealthCheckResult`, `AuditEvent` | decode(encode(x)) == x; ID encode thành chuỗi UUID thường |
| U8 | AccessToken không lộ value | `"\(token)"`, `String(reflecting:)` | không chứa `value`; chứa `<redacted>` |
| U9 | `AccessToken.isValid` biên | expiresAt = now+60, minValidity 60 | `false`; now+61 → `true` |
| U10 | `AccountStatus.severity` thứ tự | — | needsReauth > needsConsent > unreachable > degraded > healthy |
| U11 | `KeychainRef` định dạng | kind `.refreshToken`, id cố định | `account == "refreshToken.<uuid lowercase>"`, `service == "app.vdaily.keyloft"` |
| U12 | Fake trong TestSupport | `StubHTTPClient` không khớp route | throw `URLError(.unsupportedURL)`; `requests` ghi đủ; `InMemoryHealthCheckRepository.append` 51 lần → giữ 50 mới nhất |

## Integration Tests

Không có.

## Edge Cases and Failure Modes

- Scope chứa ký tự Unicode: giữ nguyên, không normalize.

## Manual Verification

Không có.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| Chỉ import Foundation | `make lint` (check-imports) |
| Sendable/Equatable/Codable | Biên dịch Swift 6 + U7 |
| U1–U12 xanh | U1–U12 |

## Regression Risk

Đổi format Codable của ID/ScopeSet sẽ làm hỏng dữ liệu DB (SPEC-003 lưu JSON). U6, U7 bắt.

## Out of Scope

Repository thật (SPEC-003).
