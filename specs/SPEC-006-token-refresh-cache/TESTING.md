# SPEC-006: Refresh, xoay vòng và cache — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

`TokenProvider`. Token endpoint encoding đã test ở SPEC-005.

## Test Environment

`swift test --filter TokenVaultTests/TokenProviderTests`. Fixture: 1 account Microsoft (rotates),
1 Google; `StubHTTPClient` có biến đếm theo URL và độ trễ tùy chọn.

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Cache hit | `seed` token hạn +3600, `accessToken` | 0 request |
| U2 | Gần hết hạn | token hạn +59, minValidity 60 | 1 request refresh, token mới |
| U3 | Không có credential active | account không credential | `.noActiveCredential` |
| U4 | Single-flight | 10 `accessToken` đồng thời, stub trễ 100 ms | đúng 1 request; 10 kết quả bằng nhau |
| U5 | Caller hủy | Task gọi `accessToken` bị cancel giữa chừng; Task khác cùng account | refresh vẫn hoàn tất 1 lần; Secret được rotate; Task thứ hai nhận token |
| U6 | Xoay vòng | stub trả `refresh_token: "rt2"` | Secret value == "rt2" khi `accessToken` trả về; `rotatedAt` set |
| U7 | Rotate lỗi 2 lần rồi ok | store fake lỗi 2 lần | thành công, 3 lần ghi |
| U8 | Rotate lỗi 3 lần | — | `.rotationPersistFailed`; account `needsReauth` |
| U9 | Transient không đổi status | 503 và `URLError(.timedOut)` | throw `.oauth` `isTransient`; status không đổi; 0 audit |
| U10 | invalid_grant | 400 invalid_grant | status `needsReauth`; cache rỗng; audit `token.refresh_failed` |
| U11 | invalid_client | 401 invalid_client | status `degraded`; audit |
| U12 | Scope bị thu hẹp từ ngoài | granted [a,b], response scope "a" | `grantedScopes == [a]`; audit `scope.reduced` scopes [b] |
| U13 | refreshIncludesScope | Microsoft vs Google | MS body có `scope=`; Google không |
| U14 | forceRefresh bỏ cache | seed token còn hạn, `forceRefresh` | 1 request; đồng thời với `accessToken` → vẫn 1 request |

## Integration Tests

Không có (đã bao bởi SPEC-008 I1).

## Edge Cases and Failure Modes

- Property test: 100 vòng, mỗi vòng chọn ngẫu nhiên (seed cố định) 1 trong {503, 500, timedOut,
  notConnected} → status không bao giờ là `needsReauth`.
- `expires_in` thiếu → hạn +3600.

## Manual Verification

1. Account Microsoft thật: refresh 3 lần liên tiếp bằng `keyloft token --force` → lần 3 vẫn thành
   công (token xoay vòng được lưu đúng).

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| 10 đồng thời → 1 request | U4, U14 |
| RT mới lưu trước khi trả | U6, U8 |
| Lỗi mạng không needsReauth | U9 + property test |
| Không lộ token ra ngoài | Review + SPEC-002 U8 |

## Regression Risk

Thay `Task {}` bằng `async let`/task group sẽ làm U5 fail — chủ ý.

## Out of Scope

Rate limit của provider.
