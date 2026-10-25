# AGENTS.md — Keyloft

Quy tắc bắt buộc cho mọi coding agent (zcode + GLM-5.3 / GLM-5.3-Flash, Claude, người).
Đọc file này trước khi làm bất kỳ task nào trong `handoff/tasks/`.

## Dự án

- Keyloft: token/secret vault cho macOS. Giai đoạn 1 = OAuth core (xem `docs/PROJECT-SPEC.md`).
- Swift 6 (language mode 6, strict concurrency), SwiftUI, macOS 14+.
- Swift Package Manager; app shell build bằng XcodeGen (`App/project.yml`).
- Bundle ID / Keychain service prefix: `app.vdaily.keyloft`.

## Đọc theo thứ tự

1. `AGENTS.md` (file này)
2. Task được giao: `handoff/tasks/Txx-*.md`
3. Các mục spec mà task trỏ tới: `specs/SPEC-NNN-*/PRODUCT.md` → `TECH.md` → `TESTING.md`
4. Code hiện có của target mà task chạm vào

Không đọc/sửa target khác ngoài danh sách "Files" của task.

## Lệnh

```bash
make build        # swift build
make test         # swift test (bỏ qua test Keychain thật)
make test-keychain  # KEYLOFT_KEYCHAIN_TESTS=1 swift test --filter SecretVaultKeychainTests
make lint         # swift-format lint --strict -r Sources Tests
make format       # swift-format format -i -r Sources Tests
swift test --filter <TargetTests>/<SuiteName>   # chạy test của task
```

Task chỉ được coi là xong khi `make build`, `make lint` và test của task đều xanh.

## Quy tắc kiến trúc (SPM ép khi build)

1. `VaultDomain` không import gì ngoài `Foundation` (ngoại lệ: `Security` trong `Infrastructure.swift`).
2. `TokenVault` → `SecretVault` → `VaultDomain`. Không có chiều ngược lại.
3. `Providers` chỉ phụ thuộc `VaultDomain`.
4. `HealthCheck` phụ thuộc `VaultDomain`, `TokenVault`, `Providers`.
5. `VaultRuntime` là composition root duy nhất (mở DB, dựng Keychain store, service). `App` và
   `KeyloftCLI` chỉ khởi tạo `VaultRuntime`, không tự `new` repository/store.
6. **Chỉ task T01 được sửa `Package.swift`.** Cần thêm dependency → dừng và ghi vào report.

## Quy tắc code

- Mọi type public: `Sendable`. Service có state → `actor`. UI model → `@MainActor @Observable`.
- Không dùng `DispatchQueue`, `@unchecked Sendable`, `nonisolated(unsafe)` trừ khi task cho phép
  rõ và có comment giải thích.
- Không dùng `Date()`, `UUID()`, `SecRandomCopyBytes` trực tiếp trong logic: đi qua
  `DateProvider`, `IDGenerator`, `RandomSource` (định nghĩa ở `VaultDomain`) để test được.
- Không dùng `URLSession` trực tiếp ngoài `URLSessionHTTPClient`; mọi gọi mạng qua `HTTPClient`.
- Lỗi: mỗi target một enum lỗi (`OAuthError`, `SecretVaultError`, `PersistenceError`...).
  Không `try?` nuốt lỗi, không `fatalError` trong code không phải test.
- Không log giá trị secret/token. `description` của type chứa secret phải che (`"<redacted>"`).
- Comment ngắn, chỉ giải thích "tại sao". Tên tiếng Anh; doc spec tiếng Việt.

## Quy tắc test

- Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`). Không XCTest.
- Mỗi case trong `TESTING.md` có ID (`U3`, `I2`) → tên test chứa ID:
  `@Test("U3: refresh trả invalid_grant → needsReauth")`.
- Không gọi mạng thật, không đụng Keychain thật trong `make test`. Dùng fake trong
  `Tests/KeyloftTestSupport` (`StubHTTPClient`, `InMemorySecretStore`, `InMemory*Repository`,
  `FixedDateProvider`, `SeededRandomSource`, `FakeBrowserSession`).
- Test Keychain thật gắn `.enabled(if: ProcessInfo.processInfo.environment["KEYLOFT_KEYCHAIN_TESTS"] == "1")`.
- Không xóa/skip test đang fail để cho xanh. Fail mà không sửa được → ghi vào report.

## Bảo mật (RFC 9700 / OWASP MASVS — không thương lượng)

- PKCE S256 bắt buộc; `state` 32 byte ngẫu nhiên, so sánh constant-time.
- Redirect chỉ `http://127.0.0.1:<port>/callback`; server loopback chỉ bind `127.0.0.1`.
- Refresh token / client secret chỉ nằm trong Keychain. SQLite chỉ có `keychainRef`.
- Access token chỉ trong RAM.
- Lỗi mạng/5xx không bao giờ đổi account sang `needsReauth`.

## Khi xong task

1. Viết report `handoff/reports/Txx.md` theo `handoff/templates/REPORT.md`, commit trên nhánh task.
2. Lệch so với TECH.md → ghi rõ trong report mục "Deviations" (không âm thầm đổi interface).
3. `handoff/BOARD.md` **chỉ sửa trên `main`** (commit riêng "board: Txx <status>"), không sửa
   trên nhánh task — tránh conflict giữa các phiên. Chế độ tự chạy: `handoff/AUTOPILOT.md`.
