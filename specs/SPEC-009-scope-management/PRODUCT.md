# SPEC-009: Quản lý scope, thu hồi và xóa account

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

Từ trạng thái `needsConsent`, người dùng bấm "Cấp thêm quyền" để chạy incremental auth đúng kiểu
từng provider. Người dùng có thể thu hẹp scope (tạo Credential hẹp, bỏ Credential cũ), thu hồi
Credential (RFC 7009) và xóa account sạch sẽ cả ở Keychain lẫn DB.

## Problem

Scope gắn với từng Credential, và mỗi provider xử lý "thêm quyền" khác nhau. Sai một chỗ là hậu
quả nặng: gọi revoke token cũ của Google sau khi cấp thêm quyền sẽ **gỡ toàn bộ grant** của client
— token mới cũng chết. Dropbox không cấp thêm scope qua URL; người dùng phải tick trong App Console
trước, nếu không đăng nhập lại cũng vô ích.

## Goals

1. "Cấp thêm quyền" làm đúng việc theo `IncrementalAuthStyle` của provider.
2. Thu hẹp scope không bao giờ làm mất quyền truy cập trước khi Credential mới hoạt động.
3. Thu hồi cảnh báo trước khi hành động có tác động toàn grant (Google).
4. Xóa account: không để lại item Keychain, Credential hay health result mồ côi.
5. Secret của Credential `superseded` được dọn sau khi Credential mới refresh thành công.

## Non-Goals

- Scope theo module/feature (giai đoạn 2 — "scope đang cần" lúc đó lấy từ manifest).
- Thu hồi phiên Microsoft qua Graph `revokeSignInSessions` (ảnh hưởng mọi app).

## Behavior

1. **Cấp thêm quyền** (account `needsConsent`, thiếu `S`):
   - Google: mở trình duyệt xin `S` với `include_granted_scopes=true`, `login_hint=email`;
     Credential mới chứa cả scope cũ + mới; Credential cũ `superseded`, **không** revoke.
   - Microsoft: chạy lại authorize với toàn bộ scope cần (cũ ∪ S).
   - Dropbox: hiện hướng dẫn "Mở App Console → Permissions → tick S → Submit, rồi bấm Tiếp tục";
     bấm Tiếp tục → đăng nhập lại.
   - Sau khi xong mà vẫn thiếu → giữ `needsConsent`, liệt kê scope còn thiếu.
2. **Thu hẹp scope**: người dùng chọn tập scope nhỏ hơn → đăng nhập mới với đúng tập đó
   (Google không gửi `include_granted_scopes`) → Credential mới active, cũ `superseded`, audit
   `scope.reduced`. Credential cũ được thu hồi nếu provider cho phép thu hồi từng token
   (Dropbox); Google thì không (vì toàn grant) — hiện ghi chú "Google giữ quyền cũ ở cấp tài khoản;
   thu hồi tại myaccount.google.com nếu muốn".
3. **Thu hồi Credential**: Dropbox → gọi API revoke; Google → hộp thoại "Thu hồi sẽ gỡ MỌI token
   của Keyloft cho account này, account sẽ cần đăng nhập lại. Tiếp tục?"; Microsoft → báo không hỗ
   trợ thu hồi từ app, hướng dẫn trang account.microsoft.com, chỉ xóa cục bộ.
   Sau thu hồi: Credential `revoked`, secret xóa, account `needsReauth` nếu không còn Credential active.
4. **Xóa account**: thu hồi (theo quy tắc 3, lỗi mạng khi thu hồi → vẫn xóa cục bộ và cảnh báo),
   xóa mọi secret của mọi Credential, xóa account (cascade credential + health), audit
   `account.removed`. Audit cũ giữ nguyên.
5. **Dọn superseded**: lần refresh thành công đầu tiên của Credential mới → xóa secret của các
   Credential `superseded` của account (giữ hàng Credential để lịch sử).

## Success Criteria

- [ ] Incremental Google không bao giờ gọi revoke endpoint (U2).
- [ ] Sau "xóa account": `security find-generic-password -s app.vdaily.keyloft` không còn item nào
      của account đó; DB không còn credential/health của account (U9, manual).
- [ ] Thu hồi Google không chạy khi chưa có `acknowledgeGrantWideRevocation = true` (U6).
- [ ] Thu hẹp scope: tại mọi thời điểm account có ≥ 1 Credential dùng được (U4).

## Validation

- Automated: test `ScopeService` với `FakeLoginRunner`, stub HTTP.
- Manual: 3 provider thật — cấp thêm quyền, xóa account.

## Open Questions

- Không có.
