# SPEC-008: Health check account

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

Kiểm tra mỗi account theo 5 tầng (có token → refresh được → gọi API được → đủ scope → cảnh báo
sớm), dừng ở tầng lỗi đầu tiên, suy ra trạng thái `healthy/degraded/needsConsent/needsReauth/
unreachable`, lưu 50 kết quả gần nhất. Chạy lúc mở app, khi máy thức dậy, mỗi 6 giờ, trước tác vụ
lớn và khi bấm "Check now" / `keyloft health`.

## Problem

Token hỏng âm thầm: Google app để chế độ Testing làm refresh token chết sau 7 ngày, client secret
Microsoft hết hạn sau 24 tháng, người dùng thu hồi quyền ở trang bảo mật của Google. Người dùng chỉ
phát hiện khi một job backup đêm thất bại. Ngược lại, báo động giả ("đăng nhập lại") mỗi lần Wi-Fi
chập chờn sẽ khiến người dùng phớt lờ mọi cảnh báo.

## Goals

1. Mỗi trạng thái có đúng một nguyên nhân rõ ràng và một hành động đề xuất.
2. Lỗi mạng / 5xx / 429 không bao giờ dẫn tới `needsReauth`.
3. Cảnh báo sớm: quota > 90%, client secret < 30 ngày, phản hồi API > 3 s.
4. Lịch chạy tự động, không chạy chồng, retry backoff khi `unreachable`.

## Non-Goals

- Kiểm tra từng file/quyền chi tiết trên Drive.
- Thông báo đẩy ra ngoài máy (email, webhook).

## Behavior

1. Mở app → tất cả account được kiểm tra (tối đa 3 song song); menu bar hiện badge theo trạng
   thái nặng nhất.
2. Bảng trạng thái (đúng bảng của spec tổng):

   | Tầng lỗi | Trạng thái | Người dùng thấy |
   | --- | --- | --- |
   | 1. Không có refresh token | needsReauth | "Đăng nhập lại" |
   | 2. `invalid_grant` | needsReauth | Thông báo hệ thống + nút đăng nhập lại 1 chạm |
   | 2. `invalid_client` | degraded | "OAuth client lỗi — cập nhật client secret" |
   | 2/3. mạng, 5xx, 429 | unreachable | "Không kết nối được, thử lại sau Xs" |
   | 3. 403 thiếu scope | needsConsent | "Cấp thêm quyền" |
   | 3. 401/403 khác | degraded | thông điệp lỗi API |
   | 4. Thiếu scope cần | needsConsent | "Cấp thêm quyền" + danh sách scope |
   | 5. quota > 90% / secret < 30 ngày / chậm | degraded | badge vàng + lý do |
   | Qua cả 5 | healthy | — |

3. Account đang `unreachable` được thử lại sau 1, 2, 4, 8, 16, 30, 30... phút; hết lỗi → về
   lịch 6 giờ bình thường.
4. Bấm "Check now" khi đang có check chạy cho account đó → không chạy thêm, nhận cùng kết quả.
5. Trạng thái đổi → audit `account.status_changed` (không ghi khi giữ nguyên).
6. Trước tác vụ lớn: nếu kết quả gần nhất < 15 phút và `healthy`/`degraded` → dùng luôn, không
   check lại.

## Success Criteria

- [ ] Mỗi hàng của bảng Behavior 2 có một test map đúng trạng thái (U2–U14).
- [ ] 1000 lần check ngẫu nhiên lỗi transient → 0 lần `needsReauth` (property test).
- [ ] 2 trigger đồng thời cho 1 account → 1 lần gọi probe.
- [ ] Sau 60 lần check vẫn chỉ 50 kết quả (dựa SPEC-003 U10, kiểm lại qua I1).
- [ ] Health check 10 account (stub trễ 200 ms) xong < 1 s với concurrency 3 (≈ 4 lượt).

## Validation

- Automated: table-driven test cho bảng trạng thái; scheduler với clock/sleeper giả.
- Manual: tắt Wi-Fi, bấm Check now → `unreachable`, không có thông báo "đăng nhập lại".

## Open Questions

- Ngưỡng "phản hồi chậm" 3 s đủ chưa? Leaning: 3 s, cấu hình trong `HealthPolicy`.
