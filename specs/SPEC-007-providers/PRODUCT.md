# SPEC-007: Providers — Google, Microsoft, Dropbox

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

Khai báo tĩnh 3 provider (endpoint, issuer, scope mặc định, quirks), đối chiếu với OIDC Discovery
khi có mạng, và cung cấp "API probe" cho health check tầng 3 (gọi 1 API nhẹ + đọc quota).

## Problem

Mỗi provider lệch chuẩn một kiểu: Google cần `access_type=offline` và trả scope `email` dạng URL;
Microsoft xoay vòng refresh token, `iss` chứa tenant, không có revoke endpoint; Dropbox cần
`token_access_type=offline` và scope quyết định ở App Console. Nếu những khác biệt này rải rác
trong `TokenVault`, thêm provider thứ tư sẽ phải sửa core.

## Goals

1. Mọi khác biệt provider nằm trong `Provider`/`ProviderQuirks` + probe; core không có
   `if provider == .google`.
2. Discovery xác nhận endpoint/issuer và cờ `authorization_response_iss_parameter_supported`.
3. Probe trả quota (dùng/tổng) cho cảnh báo > 90%.

## Non-Goals

- Provider khác (Box, pCloud...): giai đoạn sau, nhưng thiết kế phải cho phép thêm bằng 1 file.
- Duyệt file / thao tác Drive (giai đoạn 4).

## Behavior

1. Danh sách provider trong UI: Google Drive, Microsoft OneDrive, Dropbox.
2. Lúc đăng nhập, nếu discovery tải được và khác giá trị tĩnh (authURL/tokenURL/issuer) → dùng giá
   trị discovery, ghi log cảnh báo (không lộ dữ liệu người dùng). Discovery lỗi mạng → dùng tĩnh.
3. Probe:
   - Google `GET https://www.googleapis.com/drive/v3/about?fields=user,storageQuota`
   - Microsoft `GET https://graph.microsoft.com/v1.0/me/drive`
   - Dropbox `POST https://api.dropboxapi.com/2/users/get_space_usage`
   Kết quả: quota (used/total, total có thể không có — Google Workspace không giới hạn), email.
4. Probe nhận 401 → lỗi "token bị từ chối"; 403 có `insufficient_scope`/`insufficientPermissions`
   → lỗi thiếu scope; 429/5xx/mạng → lỗi tạm thời.

## Success Criteria

- [ ] `grep -rn "\.google\|\.microsoft\|\.dropbox" Sources/TokenVault Sources/HealthCheck` = 0 kết quả.
- [ ] Probe parse đúng fixture JSON thật (đã ẩn danh) của cả 3 provider (U-test).
- [ ] Discovery của 3 provider khớp giá trị tĩnh tại ngày 2026-10-25 (test fixture + manual `curl`).

## Validation

- Automated: fixture JSON trong `Tests/ProvidersTests/Fixtures/`.
- Manual: `curl` 3 discovery URL, so với fixture.

## Open Questions

- Scope Google ban đầu: `openid email https://www.googleapis.com/auth/drive` (theo "Bước tiếp theo"
  của spec tổng — chưa chốt). Dropbox: `account_info.read files.metadata.read openid email`.
  Microsoft: `openid email profile offline_access User.Read Files.ReadWrite`.
