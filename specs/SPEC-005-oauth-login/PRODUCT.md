# SPEC-005: Đăng nhập OAuth (Authorization Code + PKCE, loopback)

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

Người dùng thêm account Google/Microsoft/Dropbox bằng trình duyệt hệ thống. Keyloft chạy server
loopback `127.0.0.1:<port ngẫu nhiên>`, dùng PKCE S256 + `state` (+ `iss` khi provider hỗ trợ),
đổi code lấy token, lưu refresh token vào Keychain, ghi lại **scope thực được cấp** và định danh
account bằng `sub` của `id_token`.

## Problem

Muốn có token cho nhiều account cloud, hiện phải chạy `rclone config` cho từng cái, copy URL, và
token rơi vào file plaintext. Khi người dùng bỏ tick một scope ở màn consent (granular consent),
các công cụ hiện tại không biết — đến lúc gọi API mới lỗi 403 khó hiểu. Định danh account bằng email
gây trùng/lệch khi người dùng đổi email.

## Goals

1. Một luồng đăng nhập duy nhất cho 3 provider, tuân RFC 6749/7636/8252/9207, OIDC Core.
2. `Credential.grantedScopes` = scope trong token response; báo ngay scope bị từ chối.
3. Account định danh bằng (provider, OAuth client, `sub`); đăng nhập lại cùng `sub` không tạo
   account trùng.
4. Ba chế độ: thêm account mới, đăng nhập lại (re-auth), cấp thêm quyền (dùng bởi SPEC-009).

## Non-Goals

- Device Authorization Grant (RFC 8628) cho máy không trình duyệt — sau giai đoạn 1.
- Implicit / password grant — cấm theo OAuth 2.1.
- Xác minh chữ ký `id_token` bằng JWKS — xem Open Questions.
- Tạo OAuth client trên Console provider (người dùng tự tạo, nhập client ID/secret ở SPEC-011).

## Behavior

1. Người dùng chọn provider + OAuth client, bấm "Thêm account".
2. Keyloft mở cửa sổ trình duyệt hệ thống tới trang đăng nhập provider.
3. Người dùng đăng nhập, đồng ý. Trình duyệt chuyển về `http://127.0.0.1:<port>/callback`,
   trang hiện "Đã kết nối Keyloft — bạn có thể đóng cửa sổ này" và cửa sổ tự đóng.
4. Account xuất hiện trong danh sách với email/tên, trạng thái `healthy`.
5. Nếu scope cấp ít hơn scope xin: account vẫn được thêm, trạng thái `needsConsent`, hiện thông báo
   "Thiếu quyền: drive — tính năng Drive bị tắt" (nút "Cấp thêm quyền" ở SPEC-009).
6. Lỗi:
   - Người dùng đóng trình duyệt/hủy → không có account mới, thông báo "Đã hủy đăng nhập".
   - Không phản hồi trong 5 phút → hủy, thông báo "Hết thời gian chờ đăng nhập".
   - Provider trả `error=access_denied` → "Bạn đã từ chối quyền truy cập".
   - `state` hoặc `iss` không khớp → hủy, thông báo lỗi bảo mật, ghi audit thất bại.
   - Không có refresh token trong response → lỗi "Provider không cấp refresh token — kiểm tra cấu
     hình OAuth client" (thường do thiếu `access_type=offline` / `offline_access`).
   - Re-auth nhưng đăng nhập nhầm account khác (`sub` khác) → lỗi "Bạn đăng nhập bằng account
     khác (x@y.com)", không ghi đè account cũ.
7. Mỗi lần thành công tạo một Credential mới; Credential active cũ của account chuyển `superseded`.

## Success Criteria

- [ ] Authorize URL luôn có `code_challenge_method=S256`, `state` ≥ 43 ký tự base64url (U-test).
- [ ] Server loopback chỉ bind `127.0.0.1`, đóng ngay sau callback đầu tiên hoặc 5 phút (I-test).
- [ ] Callback sai `state` → không gọi token endpoint (stub HTTP ghi 0 request).
- [ ] Bỏ tick 1 scope → `Credential.grantedScopes` thiếu đúng scope đó, audit có `scope.denied`
      liệt kê đúng scope, account `needsConsent`.
- [ ] Đăng nhập lại cùng `sub` → số account không đổi, số credential +1, credential cũ `superseded`.
- [ ] Thêm account thật cho cả 3 provider thành công (manual, SPEC-011 + T29).

## Validation

- Automated: toàn bộ luồng chạy với `FakeBrowserSession` + `StubHTTPClient` + loopback thật.
- Manual: 3 provider thật với OAuth client của tác giả.

## Open Questions

- Xác minh chữ ký `id_token`: OIDC Core §3.1.3.7 cho phép dựa vào TLS khi `id_token` nhận trực tiếp
  từ token endpoint. Leaning: không verify chữ ký ở giai đoạn 1, nhưng **bắt buộc** kiểm tra
  `iss`, `aud`, `exp`.
