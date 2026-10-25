# T25: App: XcodeGen, ký, entitlement, WebAuth, AppContainer, lifecycle

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-011](../../specs/SPEC-011-macos-app/) | 9 | T23 |

Branch: `task/T25-app-shell` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-011 toàn bộ
- SPEC-010 TECH §1
- SPEC-005 TECH §4
- SPEC-004 TECH §4–§5

## Files (chỉ được tạo/sửa các file này)

- `App/project.yml`
- `App/Keyloft.entitlements`
- `App/Info.plist`
- `App/Local.xcconfig.example`
- `App/KeyloftApp.swift`
- `App/AppContainer.swift`
- `App/Platform/*.swift`
- `App/Features/PlaceholderView.swift`
- `App/Tests/KeyloftAppTests/SmokeTests.swift`
- `Makefile (thêm target app)`

## Deliverables

1. App menu bar chạy được (`LSUIElement`), cửa sổ sidebar 5 mục placeholder.
2. `WebAuthBrowserSession`, `SystemEvents`, `Notifier`, `Clipboard`, `CLIInstaller`, `AppContainer` (TECH §3–§4).
3. CLI `keyloft` embed và ký trong `Contents/MacOS/`.
4. Nút debug tạm (chỉ `#if DEBUG`) để thêm account Google bằng client nhập tay — chứng minh luồng thật chạy.

## Tests

KeyloftAppTests smoke + test thuần cho `Clipboard` (changeCount) và dedupe của `Notifier` (SPEC-011 U8).

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make app
xcodebuild test -scheme Keyloft
```

## Lưu ý

- Ghi trong report từng bước ký/provisioning để người khác tái lập.
- Đăng nhập Google thật bằng account của chủ dự án do NGƯỜI làm (agent không nhập mật khẩu); agent chuẩn bị build và hướng dẫn.
- Không sandbox giai đoạn 1.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T25.md` đã viết, BOARD status = `review`
