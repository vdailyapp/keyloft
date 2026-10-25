# SPEC-003: VaultPersistence — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

Schema, migration, 6 repository GRDB. Không kiểm tra Keychain.

## Test Environment

`swift test --filter VaultPersistenceTests`. `VaultDatabase.inMemory()`; file tạm cho U1, U2.
Dữ liệu mẫu: `TestData` trong `KeyloftTestSupport`.

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Mở file mới | `VaultDatabase.open(at:)` | Thư mục quyền `0700`, file `0600`, `PRAGMA journal_mode` = `wal`, migration `v1_initial` đã áp dụng |
| U2 | DB mới hơn app | Thêm tay hàng `grdb_migrations` = `"v99_future"` rồi `open` | throw `PersistenceError.schemaTooNew` |
| U3 | Ngày lưu dạng số | Lưu account `createdAt` 2 giá trị, `list()` | Thứ tự đúng theo thời gian; cột `created_at` có `typeof = real` |
| U4 | OAuthClient xóa khi còn account | `delete` | throw `DomainError.hasDependents`, client còn nguyên |
| U5 | Account unique | Lưu 2 account cùng (provider, client, externalId) khác id | lần 2 throw `PersistenceError.database` |
| U6 | `find(provider:oauthClient:externalId:)` | — | Trả đúng account; sai externalId → nil |
| U7 | Xóa account cascade | account có 2 credential + 3 health result + audit | credential & health = 0; audit giữ nguyên |
| U8 | Credential active & supersede | insert c1, c2 (issuedAt sau), `markSuperseded(c1, by: c2)` | `active == c2`; c1.status `.superseded`, `supersededBy == c2`; `markSuperseded` id lạ → `notFound` |
| U9 | Audit append-only | `UPDATE`/`DELETE` SQL thô | Lỗi chứa `append-only` |
| U10 | Health retention | 60 lần `append` cho A, 3 cho B | A còn 50 (đúng 50 `checkedAt` lớn nhất), B còn 3 |
| U11 | Health `latest`/`list(limit:)` | — | Mới nhất trước; `limit` tôn trọng |
| U12 | Audit query lọc | 10 event lẫn target/action/time | Lọc từng điều kiện và kết hợp đúng, mới nhất trước, `limit` |
| U13 | Row hỏng | Ghi tay `status='bogus'` vào account | `get` throw `PersistenceError.corruptRow(table: "account", ...)` |

## Integration Tests

| # | Scenario | Setup | Expected |
|---|----------|-------|----------|
| I1 | Hai tiến trình | 2 `VaultDatabase.open` cùng file, ghi xen kẽ 100 lần từ 2 Task | Không lỗi locked; tổng 200 bản ghi |

## Edge Cases and Failure Modes

- `list(provider: nil)` trả tất cả; danh sách rỗng trả `[]`, không throw.
- `updateStatus` account không tồn tại → `DomainError.notFound`.

## Manual Verification

1. Mở `vault.sqlite` bằng `sqlite3`, `.schema` — không có cột chứa giá trị token/secret.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| Test in-memory < 2 s | Thời gian `swift test --filter VaultPersistenceTests` |
| UPDATE/DELETE audit bị chặn | U9 |
| 60 append → 50 mới nhất | U10 |
| Schema chỉ có `*_ref` | Manual 1 |

## Regression Risk

Đổi format JSON của `ScopeSet` (SPEC-002) → U7 SPEC-002 và U8 ở đây bắt.

## Out of Scope

Hiệu năng với > 10k audit event (giai đoạn 2).
