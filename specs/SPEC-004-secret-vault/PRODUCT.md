# SPEC-004: SecretVault — Keychain và Touch ID

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

Mọi giá trị bí mật (refresh token, client secret, API key, password) nằm trong Keychain macOS dưới
service `app.vdaily.keyloft`; SQLite chỉ có metadata. Secret nhạy cảm có thể bắt Touch ID mỗi lần
đọc; app có trạng thái khóa/mở khóa Vault bằng Touch ID.

## Problem

Công cụ kiểu rclone lưu refresh token dạng plaintext trong `~/.config/rclone/rclone.conf`; ai đọc
được file là chiếm được Google Drive. Keyloft tồn tại để không có file nào như vậy. Đồng thời,
nếu mọi lần refresh đều hỏi Touch ID, health check chạy nền mỗi 6 giờ sẽ bật hộp thoại liên tục và
người dùng sẽ tắt tính năng — nên phải phân biệt secret nào cần sự hiện diện của người dùng.

## Goals

1. API thống nhất tạo/đọc/xoay vòng/xóa secret; metadata và Keychain luôn nhất quán.
2. Secret đánh dấu `requiresUserPresence` chỉ đọc được sau Touch ID / mật khẩu máy.
3. Vault khóa/mở khóa bằng Touch ID ở cấp app, tái dùng xác thực tối đa 5 phút.
4. Item Keychain không đồng bộ iCloud, chỉ trên máy này (`ThisDeviceOnly`).

## Non-Goals

- Secure Enclave key để mã hóa thêm (đánh giá lại khi có export full value, giai đoạn 3).
- Chia sẻ Keychain cho process ngoài (giai đoạn 2, Access API).
- Import secret từ 1Password/rclone.

## Behavior

1. Tạo secret: lưu vào Keychain trước, rồi metadata. Keychain lỗi → không có metadata mồ côi.
   Metadata lỗi → item Keychain vừa ghi bị xóa lại.
2. Mặc định `requiresUserPresence`: `refreshToken` = false, `clientSecret` = false,
   `apiKey` = true, `password` = true. Người dùng đổi được khi tạo `apiKey`/`password`.
3. Đọc secret `requiresUserPresence` khi Vault đang khóa → hộp thoại Touch ID với lý do cụ thể
   ("Keyloft muốn đọc API key 'OpenAI'"). Hủy → lỗi `userCanceled`, không đổi trạng thái gì.
4. Mở khóa Vault (nút trên menu bar / khi vào màn Secrets) → Touch ID; trong 5 phút sau, đọc secret
   cần presence không hỏi lại. Máy ngủ, khóa màn hình hoặc 5 phút không hoạt động → Vault khóa lại.
5. Kiểm tra "secret có tồn tại không" (health check tầng 1) không bao giờ bật Touch ID.
6. Xoay vòng secret (Microsoft refresh token mới) ghi đè giá trị, cập nhật `rotatedAt`.
7. Mọi lần tạo/xoay vòng/xóa, và đọc bởi người dùng hoặc CLI, ghi AuditEvent. Đọc nền bởi app
   (refresh) không ghi để tránh ngập log.

## Success Criteria

- [ ] Không chuỗi giá trị secret nào xuất hiện trong log, `description`, lỗi hay DB (test U8, U9).
- [ ] Item Keychain tạo ra có `kSecAttrSynchronizable = false`, accessible `*ThisDeviceOnly` (I1).
- [ ] Item `requiresUserPresence` đọc không có Touch ID → thất bại (I2, manual).
- [ ] `exists` trên item cần presence trả `true` mà không hiện hộp thoại (I3).
- [ ] Ghi metadata lỗi → không còn item Keychain mồ côi (U3).

## Validation

- Manual: chạy app đã ký, tạo API key cần presence, đọc → Touch ID; trong 5 phút đọc lại không hỏi.
- Automated: unit test với `InMemorySecretStore`; test Keychain thật bật bằng `KEYLOFT_KEYCHAIN_TESTS=1`.

## Open Questions

- CLI `keyloft token` có nên bắt Touch ID không? Leaning: không ở giai đoạn 1 (CLI đọc
  refresh token không-presence); giai đoạn 2 đi qua Access API có permission.
