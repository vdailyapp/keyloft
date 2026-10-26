# SPEC-010: VaultRuntime và CLI `keyloft` (health, token)

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

`VaultRuntime` dựng toàn bộ đồ thị đối tượng (DB, Keychain, provider, service) một lần, dùng chung
cho app và CLI. CLI giai đoạn 1 có `keyloft accounts`, `keyloft health` và `keyloft token` để
script/terminal kiểm tra trạng thái và lấy access token.

## Problem

Nếu app và CLI mỗi bên tự lắp service, chúng sẽ lệch cấu hình (khác đường dẫn DB, khác Keychain
access group) và CLI không thấy account do app tạo. Người dùng terminal (rclone, script backup) cần
một lệnh in access token mà không phải mở app.

## Goals

1. Một composition root; App và CLI chỉ khác `BrowserSession` và actor audit.
2. `keyloft health` cho exit code theo trạng thái để dùng trong cron/script.
3. `keyloft token` in đúng access token ra stdout (không gì khác) để dùng trong `$(...)`.

## Non-Goals

- `keyloft login` (cần RFC 8628 hoặc trình duyệt — sau giai đoạn 1).
- `keyloft run` / export (giai đoạn 3).
- Unix socket / Access API (giai đoạn 2): ở giai đoạn 1 CLI đọc trực tiếp DB + Keychain.

## Behavior

1. `keyloft accounts` → bảng: `ID` (8 ký tự đầu), `PROVIDER`, `EMAIL`, `STATUS`, `LAST CHECK`.
   `--json` → mảng JSON.
2. `keyloft health` → check mọi account (tối đa 3 song song), in bảng `ACCOUNT STATUS LAYER DETAIL`;
   `keyloft health <account>` chỉ 1 account; `--json` cho máy đọc.
3. `keyloft token <account>` → stdout: access token + `\n`. `--min-validity <giây>` (mặc định 60),
   `--force` bỏ cache. Mỗi lần in token → audit `token.issued` actor `cli`.
4. Chọn account bằng: UUID đầy đủ, tiền tố UUID ≥ 4 ký tự, email (không phân biệt hoa thường), hoặc
   `provider:email`. Trùng nhiều → lỗi liệt kê các ứng viên, exit 64.
5. Exit code:

   | Code | Nghĩa |
   | --- | --- |
   | 0 | healthy hoặc degraded (cảnh báo in ra stderr) |
   | 1 | lỗi khác (DB, Keychain thiếu entitlement…) |
   | 2 | needsReauth |
   | 3 | needsConsent |
   | 4 | unreachable |
   | 64 | sai cú pháp / account không tìm thấy hoặc mơ hồ |

   `health` nhiều account → code của trạng thái nặng nhất (theo `AccountStatus.severity`).
6. Mọi thông báo lỗi ra stderr, không bao giờ in refresh token/client secret.
7. Chưa có DB (chưa mở app lần nào) → "Chưa có vault. Mở Keyloft.app để thêm account." exit 1.

## Success Criteria

- [ ] `keyloft token x | wc -l` = 1 và stdout không chứa gì ngoài token (I-test bắt stdout).
- [ ] Exit code đúng bảng cho mọi trạng thái (U-test).
- [ ] Account tạo bằng app hiện ra trong `keyloft accounts` (manual, cùng máy, app đã ký).
- [ ] Luồng end-to-end login → health → token → removeAccount chạy trên GRDB thật không lỗi FK (I3).

## Validation

- Automated: `KeyloftCLITests` (parse, selector, formatter, exit code); `VaultRuntimeTests` (I1–I3).
- Manual: chạy binary embed trong app bundle.

## Open Questions

- Cách CLI chia sẻ Keychain với app: embed binary trong `Keyloft.app/Contents/Helpers/keyloft`, ký
  cùng team + entitlement `keychain-access-groups`, symlink vào `/usr/local/bin` (xem SPEC-011).
  Dev build: `KEYLOFT_DEV_LOGIN_KEYCHAIN=1` dùng login keychain.
