# SPEC-008: Health check — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

`HealthChecker`, hàm map trạng thái, `HealthScheduler`. UI badge ở SPEC-011.

## Test Environment

`swift test --filter HealthCheckTests`. `TokenProvider` thật + `StubHTTPClient` cho token endpoint;
`FakeProbe` (trả kết quả/lỗi dựng sẵn, đếm số lần gọi); `InMemory*Repository`;
`ManualSleeper` (viết trong `HealthCheckTests`); `FixedDateProvider`.

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Bảng map thuần | `status(for:warnings:)` mọi case `LayerFailure` + nil | đúng bảng TECH §2 (table-driven, 1 test nhiều argument) |
| U2 | Không credential | — | needsReauth; `checks == [tokenPresent(ok:false)]` |
| U3 | Credential có, Keychain mất item | xóa item store | needsReauth; chỉ 1 tầng |
| U4 | invalid_grant | stub 400 | needsReauth; checks 2 tầng; probe 0 lần |
| U5 | invalid_client | stub 401 | degraded |
| U6 | Refresh 503 | — | unreachable |
| U7 | Keychain locked | store throw `interactionNotAllowed` | unreachable (KHÔNG needsReauth) |
| U8 | Probe 403 insufficientScope | FakeProbe | needsConsent; 3 tầng |
| U9 | Probe 401 | — | degraded |
| U10 | Probe 429 / network | — | unreachable |
| U11 | Thiếu scope cần | grantedScopes thiếu `drive` | needsConsent; item scopes `error` nêu `drive` |
| U12 | Quota 95% | used 95 total 100 | degraded; warnings `["quota>90%"]`; 5 tầng |
| U13 | Quota không giới hạn | total nil | không cảnh báo |
| U14 | Secret còn 29 ngày / đã hết hạn / 31 ngày | client `secretExpiresAt` | degraded `clientSecret<30d` / `clientSecretExpired` / healthy |
| U15 | Chậm | probe latency 3001 | degraded `slow` |
| U16 | Healthy | tất cả ok | healthy; 5 item ok |
| U17 | Lưu & audit khi đổi status | healthy → needsReauth → needsReauth | `results` 3 bản; audit `account.status_changed` đúng 1 lần |
| U18 | Không lộ token | access token `"at-SECRET"`, ép mọi lỗi | không item `error` nào chứa `at-SECRET` |
| U19 | Dedupe | `run(.manual(A))` ×2 đồng thời | probe A gọi 1 lần; 2 kết quả bằng nhau |
| U20 | Concurrency limit | 10 account, probe trễ, đếm đồng thời tối đa | max đồng thời == 3 |
| U21 | Backoff | A unreachable liên tục | retry sau 60,120,240,480,960,1800,1800 s (theo ManualSleeper) |
| U22 | Backoff reset | unreachable 2 lần rồi healthy | retry dừng; lần unreachable sau bắt đầu lại từ 60 |
| U23 | Periodic | advance 6h | `run(.periodic)` chạy cho mọi account |
| U24 | External trigger wake | đẩy `.wake` vào stream | chạy cho mọi account |
| U25 | ensureFresh còn mới | kết quả healthy 10 phút trước | không gọi probe |
| U26 | ensureFresh cũ / needsConsent | 20 phút trước; hoặc status needsConsent | chạy check mới |

## Integration Tests

| # | Scenario | Setup | Expected |
|---|----------|-------|----------|
| I1 | GRDB thật + 60 lần check | Chạy ở `VaultRuntimeTests` (SPEC-010 I2) vì `HealthCheckTests` không được phụ thuộc `VaultPersistence` | còn 50 kết quả |

## Edge Cases and Failure Modes

- Property test: 1000 lượt, seed cố định, mỗi lượt chọn ngẫu nhiên lỗi transient ở tầng 2 hoặc 3
  → status ∈ {unreachable}; không bao giờ needsReauth.
- Account bị xóa trong lúc check chạy → `check` throw `notFound`, scheduler bỏ qua, không crash.
- `stop()` hủy vòng định kỳ và mọi retry đang chờ.

## Manual Verification

1. Tắt Wi-Fi → Check now → "Không kết nối được"; bật lại → trong ≤ 1 phút về healthy.
2. Google: thu hồi Keyloft ở myaccount.google.com/permissions → Check now → needsReauth + thông báo.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| Mỗi hàng bảng có test | U1–U16 |
| 1000 transient → 0 needsReauth | Property test |
| 2 trigger → 1 probe | U19 |
| 50 kết quả | SPEC-003 U10, I1 (SPEC-010) |
| 10 account < 1 s, concurrency 3 | U20 + đo thời gian |

## Regression Risk

Thêm case mới vào `OAuthError`/`ProbeError` mà quên map → rơi vào `refreshOther`/`apiRejected`
(degraded) — an toàn theo hướng không báo needsReauth giả.

## Out of Scope

UI thông báo.
