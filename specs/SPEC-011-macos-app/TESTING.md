# SPEC-011: App macOS — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

Hàm thuần và view model của app; checklist thủ công cho phần cần app đã ký (Keychain, Touch ID,
trình duyệt). Không UI test tự động ở giai đoạn 1.

## Test Environment

`xcodebuild test -scheme Keyloft` (target `KeyloftAppTests`). Runtime fake:
`VaultRuntime(RuntimeDependencies(database: .inMemory(), secretStore: InMemorySecretStore(), http: StubHTTPClient(), browser: FakeBrowserSession(...), authenticator: FakeAuthenticator()))`.

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Badge 5 trạng thái + rỗng | `MenuBarBadge.from` | needsReauth→red, needsConsent→orange, unreachable→gray, degraded→yellow, healthy/[]→none; hỗn hợp → nặng nhất |
| U2 | Primary action | `primaryAction(for:latest:)` | needsReauth→reauth; needsConsent→grantMore; unreachable→retry; degraded do `clientSecret<30d`→fixClient; healthy→none |
| U3 | AccountsModel.load | 2 account | `rows.count == 2`, status đúng |
| U4 | Add account thành công | FakeBrowserSession redirect | row mới; không error |
| U5 | Add account hủy | `.cancel` | error == "Đã hủy đăng nhập"; rows không đổi |
| U6 | Cập nhật từ scheduler | đẩy HealthCheckResult qua `updates` | row đổi status không cần `load()` |
| U7 | Remove Google cần xác nhận | `remove(ack: false)` | model đặt `pendingConfirmation = .grantWideRevocation`; không gọi revoke |
| U8 | Notifier dedupe | 2 lần chuyển needsReauth trong 24 h | 1 notification |
| U9 | OAuth client form validate | client ID rỗng; Dropbox redirect không port; Microsoft thiếu ngày hết hạn | lỗi tương ứng, nút Lưu tắt |
| U10 | Lưu client có secret | — | `Secret` kind clientSecret tạo, `clientSecretRef` set, giá trị không nằm trong model sau khi lưu |
| U11 | Xóa client còn account | — | thông báo "Còn N account dùng client này" |
| U12 | Secrets khóa | lock `.locked` | `rows` rỗng, `needsUnlock == true` |
| U13 | Unlock rồi tự khóa | FixedDateProvider +301 s | `rows` bị xóa khỏi state |
| U14 | Reveal tự xóa | reveal → advance 30 s | `revealed[id] == nil` |
| U15 | Health history | 3 kết quả | mới nhất trước; tầng hiển thị đúng thứ tự |
| U16 | Audit filter | lọc action `scope.denied` | chỉ event đó |

## Integration Tests

Không tự động.

## Edge Cases and Failure Modes

- Chưa có OAuth client nào → nút "+" ở Accounts dẫn tới form OAuth Clients.
- Keychain `missingEntitlement` lúc khởi động → cửa sổ lỗi giải thích build chưa ký, không crash.

## Manual Verification (chạy trong T29, app đã ký)

1. Mở app lần đầu: chỉ có icon menu bar, không có Dock icon.
2. Thêm OAuth client Google (Desktop app) + account → healthy; đếm click ≤ 4 từ menu bar.
3. Bỏ tick Drive ở consent → banner cam; "Cấp thêm quyền" → healthy.
4. Thu hồi ở myaccount.google.com → Check now → chấm đỏ + notification; bấm notification → re-auth
   → healthy.
5. Microsoft: thêm account; đặt ngày hết hạn secret = hôm nay + 10 ngày → vàng `clientSecret<30d`.
6. Dropbox: client có redirect `http://127.0.0.1:53682/callback`; thêm account → healthy.
7. Secrets: thêm API key, Hiện → Touch ID; khóa màn hình, mở → Secrets đã khóa.
8. Copy secret → sau 60 s clipboard trống (nếu chưa copy gì khác).
9. Tắt Wi-Fi → Check now → chấm xám, không notification.
10. "Cài lệnh keyloft" → `keyloft accounts` chạy từ Terminal.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| Notification → re-auth ≤ 1 s → healthy | Manual 4 |
| Thêm account ≤ 4 click | Manual 2 |
| Secrets không render khi khóa | U12, U13, Manual 7 |
| Badge đúng 5 trạng thái | U1 |
| App + CLI chung Keychain | Manual 10, SPEC-010 Manual 1 |

## Regression Risk

Đổi `primaryAction` ảnh hưởng cả menu bar lẫn notification. U2 khóa hành vi.

## Out of Scope

UI test tự động, accessibility audit (sau giai đoạn 1).
