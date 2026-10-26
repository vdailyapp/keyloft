# T30: Dọn nợ review T01–T26: `try?` nuốt lỗi, print debug, chặn bằng lint

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | SPEC-003, 006, 008, 009, 011 | 10 | T26 |

Branch: `task/T30-hardening-cleanup` · Prompt: `handoff/templates/PROMPT-PRO.md`

Task này sinh ra từ review code T01–T26 (2026-10-26). Không thêm tính năng; chỉ sửa chỗ vi phạm
`AGENTS.md` ("Không `try?` nuốt lỗi", "Không log", "Không `Date()`/`UUID()` trong logic").

## Đọc trước

- `AGENTS.md` (Quy tắc code, Bảo mật)
- SPEC-006 TECH §refresh (map lỗi `invalid_grant`)
- SPEC-009 TECH §`narrow`, §`revoke`, §`removeAccount` (dòng "Lỗi mạng khi revoke → throw")
- SPEC-008 TECH §HealthScheduler
- SPEC-011 TECH §5 (Accounts model, hiển thị lỗi)

## Files (chỉ được tạo/sửa các file này)

- `Sources/TokenVault/OAuthLoginService.swift`
- `Sources/TokenVault/TokenProvider.swift`
- `Sources/TokenVault/ScopeService.swift`
- `Sources/HealthCheck/HealthScheduler.swift`
- `Sources/VaultPersistence/VaultDatabase.swift`
- `App/Features/Accounts/*.swift`, `App/Features/MenuBar/*.swift`
- `App/Platform/Notifier.swift`, `App/Platform/Clipboard.swift`, `App/AppContainer.swift`
- Test tương ứng trong `Tests/*Tests/` và `App/Tests/KeyloftAppTests/`
- `scripts/lint-rules.sh` (mới), `Makefile` (chỉ target `lint`)

## Deliverables

### 1. Xóa print debug

- `OAuthLoginService.swift:151`: `print("TRACE caught-as-BSE ...")`
- `AccountsModel.swift:98`: `print("ADD-MODEL-DEBUG ...")`

### 2. Sửa từng `try?`: làm đúng như bảng, không tự chọn cách khác

| Vị trí | Bug | Sửa |
| --- | --- | --- |
| `TokenProvider.swift:144` (`invalid_grant`) | `updateStatus(.needsReauth)` lỗi bị nuốt → account vẫn `active` dù RT đã chết | Xóa cache trước, rồi `try await updateStatus`, rồi audit, giống nhánh `invalidClient`. Lỗi persistence thì throw lỗi đó |
| `ScopeService.swift:155–156` (Dropbox narrow) | Revoke lỗi vẫn chạy `finalizeRevocation` → xóa RT cũ ở máy trong khi RT **vẫn sống ở Dropbox**, không thử lại được | Chỉ `finalizeRevocation` khi revoke thành công. Revoke lỗi: giữ credential cũ (`superseded`) cùng secret, ghi audit `credentialRevoked` với `result: .failure`, trả kết quả cho UI biết "chưa thu hồi được" (thêm field vào outcome nếu cần, ghi Deviations) |
| `ScopeService.swift:254` (`cleanupSuperseded` sau refresh) | Lỗi dọn bị nuốt | Giữ best-effort (login đã xong) nhưng ghi audit `.failure` cho từng secret dọn lỗi; không throw |
| `ScopeService.swift:266`, `:300` (`purgeValue`) | Secret mồ côi trong Keychain mà không ai biết | `:300` (`finalizeRevocation`): `try await`. `:266`: best-effort + audit `.failure`. Hành vi `removeAccount` vẫn đúng SPEC-009 (lỗi mạng → `.localOnly`, `leftoverSecrets` liệt kê secret còn sót) |
| `HealthScheduler.swift:85` | `accounts.list()` lỗi → lặng lẽ không check gì | Không nuốt: lỗi đi ra kết quả run (hoặc audit/log lỗi theo đúng kênh lỗi hiện có của scheduler); vòng 6h vẫn chạy tiếp |
| `VaultDatabase.swift:45` (chmod 0600) | Không chmod được → DB vẫn mở với quyền rộng | `try`, throw `PersistenceError`. Áp quyền 0600 cả cho `-wal` và `-shm` nếu đã tồn tại |
| `AccountsModel` (`relogin`, `grantMore`), `AccountDetailModel` (`load`, các action), `MenuBarView:24,26` | Đăng nhập lại/cấp thêm scope lỗi → UI im lặng | `do/catch`, gán `error` hiển thị cho người dùng (dùng chung hàm map lỗi đang có trong `add`) |

Các `try?` **được giữ** (có lý do), mỗi chỗ phải có comment `// try?: <lý do>` trên cùng dòng
hoặc dòng ngay trên:

- giải mã error body/JSON tùy chọn: `TokenEndpointClient:159,185`, `IDToken:59,82`, `*Probe.swift`
- bồi hoàn: `OAuthLoginService:319`, `SecretVault:73`, `VaultDatabase:42` (`pool.close` khi migrate lỗi)
- `HealthScheduler:145,191` (`sleeper.sleep`, cancel là bình thường), `:161,168` nếu kết quả lỗi đã được ghi ở nơi khác (kiểm tra; không phải thì sửa)
- `CLIInstaller`, `Clipboard:25`, `Notifier:41,46`: hành động UI best-effort

### 3. `Date()`/`UUID()` trong App

- `Notifier`: nhận `DateProvider` (mặc định `SystemDateProvider()`), thay `Date()` ở dòng 32, 42.
- `AppContainer.swift:97`: dùng `IDGenerator` của runtime.
- `Clipboard`: thay closure `now` bằng `DateProvider`.
- Bỏ `rawErrorForTest` khỏi `AccountsModel`: test kiểm `error` (chuỗi hiển thị), hoặc lưu lỗi gốc ở kiểu `OAuthError?` dùng được cho cả UI.

### 4. Chặn tái phạm bằng lint

`scripts/lint-rules.sh` (bash, `set -euo pipefail`), gọi trong `make lint` sau swift-format. Fail khi:

- có `print(` trong `Sources/` hoặc `App/` (trừ `Sources/KeyloftCLI/` đi qua `StandardStreams`)
- có `try?` trong `Sources/` hoặc `App/` (không tính `Tests`) mà dòng đó và dòng ngay trên đều không có `// try?:`
- có `Date()` hoặc `UUID()` trong `Sources/` hoặc `App/` ngoài `Sources/VaultDomain/Infrastructure.swift` và `VaultLock.swift` (key continuation nội bộ, thêm comment `// lint-allow: <lý do>`)

Script in `file:line` cho từng vi phạm.

## Tests

Thêm test hồi quy (ID tiếp nối TESTING.md của spec tương ứng; ghi ID mới vào report):

- SPEC-006: `invalid_grant` + `updateStatus` throw → `refresh` throw lỗi persistence, cache vẫn rỗng.
- SPEC-009: Dropbox narrow, revoke trả lỗi mạng → credential cũ **không** `revoked`, secret cũ vẫn còn, audit `.failure`.
- SPEC-009: `finalizeRevocation` purge lỗi → throw.
- SPEC-008: `accounts.list()` throw → lỗi hiện ra (không phải 0 account im lặng).
- SPEC-003: chmod lỗi → `open` throw (dùng thư mục chỉ đọc).
- SPEC-011: `relogin` lỗi → `AccountsModel.error != nil`.

## Verify

```bash
make build
make lint          # gồm scripts/lint-rules.sh, phải xanh
make test
make app
make app-test
```

## Lưu ý

- Không đổi interface public ngoài phần cần cho bảng ở mục 2. Có đổi thì ghi vào BOARD "Ghi chú thay đổi interface".
- Không động tới `Makefile` target `app`/`embed-cli`, `App/project.yml`, `App/Local.xcconfig*` (đã sửa ký thật trên main).

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test hồi quy ở mục Tests
- [ ] `grep -rn 'try?' Sources App --include='*.swift' | grep -v Tests` mọi dòng còn lại đều có `// try?:`
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T30.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
