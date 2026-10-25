# SPEC-002: VaultDomain — entity và protocol gốc

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

Định nghĩa một lần mọi entity giai đoạn 1 (Provider, OAuthClient, Account, Credential, Secret,
AccessToken, HealthCheckResult, AuditEvent), kiểu `ScopeSet` và các protocol repository/hạ tầng
mà các target khác dùng chung. Không có logic I/O.

## Problem

Mọi target sau đều nói chuyện bằng các type này. Nếu mỗi agent tự định nghĩa lại (ví dụ scope là
`[String]` ở chỗ này, `Set<String>` ở chỗ kia; status là `String`), tích hợp sẽ vỡ ở tuần cuối.
Scope là trung tâm của yêu cầu ("lưu scope thực được cấp", "khoảng thiếu = cần − granted") nên
phép so sánh scope phải nằm ở một chỗ, có test.

## Goals

1. Entity khớp bảng "Thực thể giai đoạn 1" trong `docs/PROJECT-SPEC.md`.
2. `ScopeSet` chuẩn hóa scope (tách theo khoảng trắng, bỏ trùng, so sánh không phụ thuộc thứ tự).
3. Protocol repository đủ cho SPEC-003..009 mà không cần sửa lại.
4. Hạ tầng tiêm được (`DateProvider`, `IDGenerator`, `RandomSource`, `HTTPClient`) để test tất định.

## Non-Goals

- Thực thể giai đoạn 2–3 (`Permission`, `ExportProfile`...).
- Validation nghiệp vụ phức tạp (thuộc service).

## Behavior

Không có hành vi người dùng trực tiếp. Hành vi quan sát được qua API:

1. `ScopeSet("openid  email email")` → 2 phần tử; `.spaceDelimited` → `"email openid"` (sắp xếp).
2. `required.missing(in: granted)` → các scope cần mà chưa được cấp.
3. Mọi entity encode/decode JSON vòng tròn không mất dữ liệu.
4. `description` của `AccessToken` không lộ `value`.

## Success Criteria

- [ ] `VaultDomain` chỉ `import Foundation` (check-imports xanh).
- [ ] Mọi type public là `Sendable`, `Equatable`; entity là `Codable`.
- [ ] Test U1–U12 trong TESTING.md xanh.

## Validation

- Automated: test ScopeSet, Codable round-trip, redaction.

## Open Questions

- Không có.
