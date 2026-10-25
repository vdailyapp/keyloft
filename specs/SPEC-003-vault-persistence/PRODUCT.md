# SPEC-003: VaultPersistence — SQLite metadata

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

Lưu metadata (OAuth client, account, credential, secret metadata, kết quả health check, audit)
vào SQLite qua GRDB, có migration, để app và CLI cùng đọc một nguồn. Không bao giờ lưu giá trị bí
mật vào DB.

## Problem

Nếu không có kho metadata bền vững, mỗi lần mở app người dùng phải đăng nhập lại mọi account, và
không biết refresh token nào thuộc account nào. Audit log mà sửa/xóa được thì vô nghĩa khi điều tra
"ai đã lấy token lúc 3 giờ sáng". Lịch sử health check không giới hạn sẽ làm DB phình mãi (4 lần/ngày
× nhiều account × nhiều năm).

## Goals

1. Triển khai đủ 6 protocol repository của SPEC-002.
2. Migration có version, chạy lại an toàn (idempotent) khi mở DB.
3. Audit chỉ ghi thêm — SQLite chặn UPDATE/DELETE bằng trigger.
4. Mỗi account giữ đúng 50 HealthCheckResult mới nhất.

## Non-Goals

- Mã hóa DB (SQLCipher): metadata không phải bí mật; bí mật ở Keychain. Xem lại ở giai đoạn 2.
- Đồng bộ nhiều máy.
- Bảng của giai đoạn 2–3.

## Behavior

1. App/CLI mở `~/Library/Application Support/app.vdaily.keyloft/vault.sqlite`; thư mục chưa có thì
   tạo với quyền `0700`, file `0600`.
2. DB cũ hơn → migration chạy tự động; DB mới hơn bản app (downgrade) → báo lỗi
   `PersistenceError.schemaTooNew`, không ghi gì.
3. App và CLI mở cùng lúc → WAL mode, cả hai đọc/ghi được, không lỗi `database is locked` trong
   điều kiện thường (busy timeout 5 s).
4. Xóa account → credential và health result của nó biến mất; audit giữ nguyên.
5. Xóa OAuth client còn account → lỗi `hasDependents`, không xóa gì.

## Success Criteria

- [ ] Toàn bộ test repository chạy trên DB in-memory, < 2 s tổng.
- [ ] `UPDATE audit_event ...` hoặc `DELETE FROM audit_event` thô → SQLite trả lỗi (test U9).
- [ ] Sau 60 lần `append` health cho 1 account, `COUNT(*) == 50` và còn đúng 50 bản mới nhất.
- [ ] `grep -i "token\|secret" schema` chỉ thấy cột `*_ref` (review migration).

## Validation

- Automated: test repository trên `DatabaseQueue()` in-memory; test migration trên file tạm.

## Open Questions

- Đường dẫn DB khi sau này bật App Sandbox (app group container). Leaning: giai đoạn 1 không
  sandbox; `VaultDatabase.defaultURL()` là điểm duy nhất cần đổi.
