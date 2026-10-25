# SPEC-006: Refresh token, xoay vòng và cache access token

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

Một chỗ duy nhất (`TokenProvider`) trả access token còn hạn cho account: dùng cache RAM nếu còn
≥ 60 s, ngược lại refresh. Lưu refresh token mới ngay khi provider xoay vòng (Microsoft). Nhiều
yêu cầu cùng lúc cho một account chỉ gây **một** lần refresh.

## Problem

Microsoft xoay vòng refresh token: nếu hai tác vụ refresh song song bằng cùng token cũ, hoặc token
mới không được lưu kịp, account mất quyền và người dùng phải đăng nhập lại — đây là lỗi điển hình
khiến rclone "tự nhiên" đòi `rclone config reconnect`. Ngược lại, refresh mỗi lần cần token sẽ
chạm rate limit và chậm.

## Goals

1. Access token chỉ nằm trong RAM; không ghi đĩa, không log.
2. Single-flight theo account; caller hủy không làm hủy refresh đang chạy.
3. Refresh token mới được lưu vào Keychain trước khi trả access token.
4. `invalid_grant` → account `needsReauth`; lỗi mạng/5xx không đổi trạng thái.

## Non-Goals

- Cấp token hẹp cho module (RFC 8693, giai đoạn 2).
- Refresh chủ động theo lịch (health check SPEC-008 đã chạy định kỳ).

## Behavior

1. Gọi `accessToken(for:)` khi cache còn hạn → trả ngay, không gọi mạng.
2. Hết hạn/sắp hết (≤ 60 s) → refresh bằng Credential active của account.
3. 10 lời gọi đồng thời → 1 request tới token endpoint, 10 caller nhận cùng token.
4. Provider trả refresh token mới → ghi đè Secret (cùng `keychainRef`), `rotatedAt` cập nhật.
   Ghi lỗi → thử lại 3 lần; vẫn lỗi → account `needsReauth`, báo lỗi rõ.
5. Response refresh có `scope` hẹp hơn `grantedScopes` (bị thu bớt từ ngoài) → cập nhật
   `grantedScopes`, audit `scope.reduced`.
6. `invalid_grant` → account `needsReauth`, cache xóa, audit `token.refresh_failed`.
7. `invalid_client` (vd client secret Microsoft hết hạn) → account `degraded`, audit
   `token.refresh_failed`, lỗi gợi ý cập nhật client secret.
8. Mất mạng / 5xx → lỗi `isTransient`, trạng thái account giữ nguyên.

## Success Criteria

- [ ] 10 lời gọi đồng thời → đúng 1 request refresh (U4).
- [ ] Response có refresh token mới → Secret chứa token mới trước khi `accessToken` trả về (U6).
- [ ] Lỗi mạng không bao giờ ghi `needsReauth` (U9, property test 100 lần với lỗi ngẫu nhiên transient).
- [ ] Không có API nào trả AccessToken ra ngoài process ở giai đoạn 1 ngoài CLI `keyloft token`.

## Validation

- Automated: unit test với StubHTTPClient đếm request, độ trễ giả lập.

## Open Questions

- `invalid_client` có nên là trạng thái riêng (`clientInvalid`)? Leaning: không thêm ở giai đoạn 1,
  dùng `degraded` + thông điệp.
