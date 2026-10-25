# SPEC-007: Providers — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

Khai báo provider, discovery, probe. Luồng OAuth dùng provider ở SPEC-005.

## Test Environment

`swift test --filter ProvidersTests`. Fixture JSON trong `Tests/ProvidersTests/Fixtures/`
(load bằng `Bundle.module`). Fixture probe ẩn danh: email `user@example.com`, số quota giả.

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Bảng giá trị tĩnh | `Provider.google/.microsoft/.dropbox` | Từng field khớp bảng TECH §2 |
| U2 | Không ai ghi đè tham số bảo mật | mọi `extraAuthParams` | không chứa key `state`, `code_challenge`, `redirect_uri`, `client_id`, `response_type`, `scope` |
| U3 | `ProviderCatalog.provider` | `.dropbox` | trả Dropbox; catalog rỗng → `DomainError.notFound` |
| U4 | Scope offline | Microsoft defaultScopes | chứa `offline_access`; Google/Dropbox có param offline |
| U5 | Decode discovery 3 fixture | `DiscoveryDocument` | các field không nil như fixture |
| U6 | Merge cùng issuer | doc tokenEndpoint khác | provider mới dùng endpoint của doc; quirks khác giữ nguyên |
| U7 | Merge issuer lạ | doc.issuer = `https://evil` | trả provider tĩnh y nguyên |
| U8 | Không S256 | doc `code_challenge_methods_supported: ["plain"]` | bỏ doc |
| U9 | Discovery lỗi mạng | stub throw | `refreshDiscovery()` không throw; `provider()` trả tĩnh |
| U10 | Google about OK | fixture | email, used, total đúng; request có Bearer, đúng URL fields |
| U11 | Google không limit | fixture bỏ `limit` | `total == nil` |
| U12 | Google 403 insufficientPermissions | fixture | `.insufficientScope` |
| U13 | MS drive OK | fixture | quota đúng; email nil được |
| U14 | MS 403 + WWW-Authenticate insufficient_scope | — | `.insufficientScope` |
| U15 | Dropbox space usage individual & team | 2 fixture | `total` đúng; request POST không body, không Content-Type |
| U16 | Dropbox 401 missing_scope | fixture | `.insufficientScope("files.metadata.read")` |
| U17 | 401 thường | 3 provider | `.unauthorized` |
| U18 | 429 / 503 / URLError | — | `.rateLimited`/`.server(503)`/`.network`, `isTransient == true` |
| U19 | latency | FixedDateProvider advance trong stub | `latencyMs` đúng |

## Integration Tests

Không (không gọi mạng thật trong test).

## Edge Cases and Failure Modes

- JSON thừa field lạ → bỏ qua. Số quota dạng string (Google) và int (MS/Dropbox).
- 200 nhưng JSON hỏng → `.malformed`.

## Manual Verification

1. `curl -s <discoveryURL> | jq '{issuer, authorization_endpoint, token_endpoint, revocation_endpoint, authorization_response_iss_parameter_supported}'`
   cho 3 provider; so với bảng TECH §2, cập nhật fixture.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| Không `if provider ==` trong core | grep trong `make lint` (thêm vào check-imports.sh ở T19) |
| Probe parse fixture 3 provider | U10–U16 |
| Discovery khớp tĩnh | U5, U6, Manual 1 |

## Regression Risk

Đổi `defaultScopes` → account cũ có thể bị `needsConsent`. Thay đổi phải ghi trong PR.

## Out of Scope

Gọi API thật.
