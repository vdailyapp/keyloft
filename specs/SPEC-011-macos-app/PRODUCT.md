# SPEC-011: App macOS — menu bar và các màn hình giai đoạn 1

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

App menu bar `Keyloft.app` (bundle `app.vdaily.keyloft`): xem trạng thái mọi account trong nháy mắt,
thêm/xóa account, đăng nhập lại 1 chạm, cấp thêm quyền, quản lý OAuth client và secret, xem lịch sử
health check và audit. Vault mở khóa bằng Touch ID.

## Problem

Toàn bộ core vô dụng nếu người dùng không thấy account nào sắp hỏng và không sửa được trong vài
giây. Hiện tại người dùng phát hiện token chết khi job lỗi, rồi mất 10 phút tìm lại lệnh
`rclone config reconnect`.

## Goals

1. Badge menu bar phản ánh trạng thái nặng nhất trong ≤ 1 s sau khi health check xong.
2. Mỗi trạng thái lỗi có đúng một nút hành động chính.
3. Thêm account mới ≤ 4 lần bấm (sau khi đã có OAuth client).
4. Màn Secrets chỉ mở sau Touch ID; tự khóa khi ngủ/khóa màn hình/5 phút.

## Non-Goals

- Màn Modules/Exports (giai đoạn 2/3) — không tạo thư mục rỗng.
- Đa ngôn ngữ: giai đoạn 1 chỉ tiếng Việt (chuỗi vẫn đi qua `String(localized:)` để dịch sau).
- Onboarding wizard tạo OAuth client trên Console.

## Behavior

1. **Menu bar** (`MenuBarExtra`, style `.window`): icon chìa khóa; chấm màu theo trạng thái nặng nhất
   (đỏ: needsReauth; cam: needsConsent; xám: unreachable; vàng: degraded; không chấm: healthy).
   Popover: danh sách account (icon provider, email, trạng thái, lần check gần nhất), nút hành động
   chính theo trạng thái, "Check now", "Mở Keyloft…", "Thoát".
2. **Cửa sổ chính** (`Window`, sidebar): Accounts · OAuth Clients · Secrets · Health · Audit.
3. **Accounts**: nút "+" → chọn provider → chọn OAuth client (hoặc "Thêm client…") → trình duyệt
   mở → xong hiện account. Thiếu scope → banner cam "Thiếu quyền: …" + "Cấp thêm quyền". Chi tiết
   account: credential (active/superseded/revoked, scope cấp), nút "Thu hẹp quyền…", "Thu hồi…",
   "Xóa account…" (xác nhận; Google có cảnh báo toàn grant).
4. **OAuth Clients**: danh sách theo provider; form: label, client ID, client secret (SecureField,
   tùy chọn), redirect URI (mặc định `http://127.0.0.1/callback`; Dropbox yêu cầu nhập cổng cố
   định, có gợi ý), ngày hết hạn secret (bắt buộc hiển thị cho Microsoft). Link hướng dẫn tạo client
   cho từng provider; với Google nhắc "Chuyển app sang In production, nếu không token hết hạn sau 7
   ngày".
5. **Secrets**: khóa → màn "Mở khóa bằng Touch ID". Mở → danh sách secret (kind, label, ngày tạo/
   xoay vòng), thêm API key/password (presence mặc định bật), "Hiện" (Touch ID nếu cần), "Copy"
   (tự xóa clipboard sau 60 s), xóa. Refresh token chỉ hiện metadata, không có nút Hiện.
6. **Health**: chọn account → 50 kết quả gần nhất, mỗi kết quả mở ra 5 tầng (ok/lỗi/latency/cảnh
   báo). Nút "Check now".
7. **Audit**: bảng event mới nhất trước, lọc theo account, action, khoảng thời gian.
8. **Thông báo hệ thống**: account chuyển sang `needsReauth` → notification "Google x@y cần đăng
   nhập lại" + action "Đăng nhập lại" mở luồng re-auth trực tiếp. Không gửi lại cho cùng account
   trong 24 giờ nếu trạng thái không đổi.
9. **Vòng đời**: mở app → `appLaunch` health; `NSWorkspace.didWakeNotification` → `wake`;
   `screensDidSleep`/`sessionDidResignActive`/`willSleep` → khóa Vault.
10. Lần đầu mở: Login item tùy chọn ("Mở cùng macOS"); nút "Cài lệnh keyloft" tạo symlink
    `/usr/local/bin/keyloft` (cần quyền admin → hướng dẫn copy lệnh nếu bị từ chối).

## Success Criteria

- [ ] Từ `needsReauth`, bấm notification → trình duyệt mở trong ≤ 1 s, xong → healthy (manual).
- [ ] Thêm account Google mới: ≤ 4 click từ menu bar (manual đếm).
- [ ] Secrets không render danh sách khi Vault khóa (UI test/preview + manual).
- [ ] Badge đúng màu cho 5 trạng thái (U-test trên hàm thuần `MenuBarBadge.from(statuses)`).
- [ ] App + CLI embed dùng chung Keychain (SPEC-010 Manual 1).

## Validation

- Automated: unit test cho view model (hàm thuần + model với runtime fake). Không UI test tự động
  ở giai đoạn 1.
- Manual: checklist T29.

## Open Questions

- XcodeGen hay Tuist? Leaning: XcodeGen (`App/project.yml`), không commit `.xcodeproj`.
