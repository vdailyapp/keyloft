# SPEC-001: Khung SPM, CI và hạ tầng test

**Status:** Draft
**Owner:** @Nguyên Phạm
**Last updated:** 2026-10-25

## Summary

Dựng repo Swift Package với đủ target giai đoạn 1, lint, CI và bộ fake dùng chung cho test,
để mọi task sau chỉ việc thêm code vào target có sẵn mà không ai phải sửa `Package.swift`.

## Problem

Công việc giai đoạn 1 được chia cho nhiều agent chạy song song (GLM-5.3, GLM-5.3-Flash). Nếu
mỗi task tự thêm target/dependency, `Package.swift` sẽ xung đột liên tục và quy tắc phụ thuộc
(VaultDomain là gốc, TokenVault → SecretVault) bị phá mà không ai thấy. Không có fake chung thì
mỗi task tự viết stub HTTP/Keychain riêng, test không nhất quán.

## Goals

1. Một lần khai báo toàn bộ target giai đoạn 1 với đúng đồ thị phụ thuộc.
2. `make build`, `make test`, `make lint` chạy được ngay trên repo trống, local và CI.
3. Có target `KeyloftTestSupport` chứa chỗ đặt fake dùng chung.

## Non-Goals

- Target giai đoạn 2–4 (`ModuleHost`, `AccessAPI`, `MCPServer`, `Exporters`, `StorageModule`):
  không khai báo, tránh code chết.
- Xcode project cho app (SPEC-011).
- Release/notarize.

## Behavior

1. Clone repo, chạy `make build` → build thành công mọi target, không warning concurrency.
2. `make test` → mỗi test target có 1 smoke test, tất cả pass, không cần mạng/Keychain.
3. `make lint` → swift-format kiểm tra `Sources/` và `Tests/`; sai format thì exit ≠ 0.
4. Push/PR lên GitHub → workflow `ci.yml` chạy build + lint + test trên `macos-14`.
5. Thêm `import TokenVault` vào `SecretVault` → build fail (SPM chặn vì không khai báo dependency).

## Success Criteria

- [ ] `swift build` xanh với Swift 6 language mode, `-warnings-as-errors` bật trong CI.
- [ ] `swift test` xanh, ≥ 1 test mỗi test target, chạy < 60 s trên máy dev.
- [ ] Đồ thị dependency trong `Package.swift` khớp đúng bảng ở TECH.md (review bằng mắt + U2).
- [ ] CI chạy trên PR, thời gian < 10 phút.

## Validation

- Manual: clone sạch, chạy 3 lệnh make.
- Automated: smoke test mỗi target; test U2 kiểm tra import bị cấm bằng script.

## Open Questions

- GRDB bản 7.x (Swift 6 ready) — chọn `from: "7.0.0"`. Nếu GLM gặp lỗi build, pin bản cụ thể.
