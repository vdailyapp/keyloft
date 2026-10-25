# Keyloft — Spec dự án

Oct 25, 2026 · @Nguyên Phạm

> Đây là spec tổng (nguồn sự thật cho phạm vi). Spec chi tiết từng phần nằm ở `specs/SPEC-NNN-*`,
> việc chia task cho agent nằm ở `handoff/`. Khi spec chi tiết mâu thuẫn với file này, sửa
> một trong hai — không để lệch.

Giai đoạn 1 chỉ làm phần quản lý OAuth: Provider, OAuth client, Account, Credential, scope và health check. Module, Access API, export và storage để các giai đoạn sau. Tên dự án: Keyloft — mã nguồn mở tại github.com/vdailyapp/keyloft, CLI keyloft, bundle ID app.vdaily.keyloft (cũng là Keychain prefix).

## Phạm vi & giai đoạn

Mã nguồn mở cho tổ chức vdailyapp, dùng cá nhân, không thương mại; core là Token Vault + Secret Vault, storage chỉ là module gắn ngoài.

| Giai đoạn | Nội dung | Kết quả dùng được |
| --- | --- | --- |
| **1. OAuth core** | SecretVault, Provider, OAuthClient, Account, Credential, scope, health check | Thêm/xóa account nhiều provider, xem trạng thái, đăng nhập lại |
| 2. ModuleHost & Access API | Manifest, Permission, AuditEvent, Unix socket, MCP server | Process ngoài lấy token có kiểm soát |
| 3. Export | Exec, reference, full value; rclone.conf, dotenv, ADC | App khác dùng chung account |
| 4. Storage module | rclone rcd, quota, duyệt file, rebalance | Quản lý và cân bằng dung lượng |

Provider giai đoạn 1: Google, Microsoft, Dropbox. Ngôn ngữ: Swift 6 + SwiftUI, macOS 14+.

## Thực thể giai đoạn 1

Giá trị bí mật chỉ nằm trong Keychain; SQLite chỉ giữ metadata và `keychainRef`. Credential tách khỏi Account vì một Account có nhiều grant.

| Thực thể | Trường chính | Ghi chú |
| --- | --- | --- |
| Provider | `id`, `authURL`, `tokenURL`, `revokeURL`, `discoveryURL`, `defaultScopes`, `quirks` | Tĩnh, nạp trong code. `quirks`: `rotatesRefreshToken`, `needsOfflineParam` |
| OAuthClient | `id`, `providerId`, `clientId`, `clientSecretRef → Secret`, `redirectURI`, `secretExpiresAt`, `label` | Client ID tự tạo; `secretExpiresAt` cho Microsoft (tối đa 24 tháng) |
| Account | `id`, `providerId`, `oauthClientId`, `externalId` (`sub`), `email`, `displayName`, `status` | `status`: healthy, degraded, needsConsent, needsReauth, unreachable |
| Credential | `id`, `accountId`, `refreshTokenRef → Secret`, `requestedScopes`, `grantedScopes`, `issuedAt`, `supersededBy`, `status` | Mỗi lần OAuth thành công là một Credential |
| Secret | `id`, `kind`, `label`, `keychainRef`, `requiresUserPresence`, `createdAt`, `rotatedAt` | `kind`: apiKey, password, clientSecret, refreshToken |
| AccessToken | `value`, `scopes`, `expiresAt` | Chỉ cache trong RAM |
| HealthCheckResult | `id`, `accountId`, `checkedAt`, `status`, `checks[{name, ok, latencyMs, error}]` | Giữ 50 kết quả gần nhất mỗi account |
| AuditEvent | `id`, `actor`, `action`, `target`, `scopes`, `result`, `timestamp` | Chỉ ghi thêm; có `scope.granted`, `scope.denied`, `scope.reduced` |

Quan hệ: `Provider 1—n OAuthClient 1—n Account 1—n Credential → Secret(refreshToken)`; `OAuthClient → Secret(clientSecret)`; `Account 1—n HealthCheckResult`.

## Luồng OAuth

Authorization code + PKCE qua trình duyệt hệ thống, redirect loopback; lưu scope thực được cấp, không phải scope đã xin.

1. Tạo `code_verifier`, `code_challenge` (S256) và `state`; mở server loopback `127.0.0.1:<port ngẫu nhiên>`.
2. Mở authorize URL bằng `ASWebAuthenticationSession`.
3. Callback: kiểm tra `state` và `iss` (nếu có), đổi code lấy token.
4. Đọc `scope` trong token response → `Credential.grantedScopes`; so với `requestedScopes` để phát hiện scope bị bỏ tick.
5. Lấy `sub` từ `id_token` làm `Account.externalId` (email có thể đổi).
6. Ghi refresh token vào Keychain làm Secret; ghi AuditEvent.

Khác biệt từng provider:

| Provider | Lưu ý |
| --- | --- |
| Google | App OAuth phải ở trạng thái **In production**; để Testing thì refresh token hết hạn sau 7 ngày. 1 project đủ cho mọi account cá nhân (giới hạn 100 user) |
| Microsoft | Xoay vòng refresh token: lưu token mới sau mỗi lần refresh. Client secret hết hạn tối đa 24 tháng |
| Dropbox | Cần `token_access_type=offline` để có refresh token; scope do App Console quyết định |

## Quản lý scope

Scope gắn với từng Credential, không gắn với Account. Khoảng thiếu scope = scope đang cần trừ `grantedScopes`.

| Tình huống | Điều xảy ra | Xử lý |
| --- | --- | --- |
| Cần thêm scope | API trả 403 `insufficient_scope` | `needsConsent` → nút "Cấp thêm quyền" → incremental auth |
| Người dùng bỏ tick scope (granular consent) | Token thiếu scope | So sánh ngay sau callback, báo tính năng bị tắt |
| Thu hồi từ bên ngoài | Refresh trả `invalid_grant` | `needsReauth` |
| Muốn giảm scope | Token cũ còn quyền rộng | Tạo Credential mới scope hẹp, bỏ Credential cũ (`supersededBy`) |
| Sửa cấu hình OAuth client trong Console | Token đang có không đổi | Có tác dụng ở lần đăng nhập kế tiếp |

Incremental auth theo provider:

- **Google:** gửi `include_granted_scopes=true`; refresh token mới bao cả scope cũ và mới → ghi đè Secret. Không gọi revoke token cũ: có thể gỡ toàn bộ grant của client.
- **Microsoft:** refresh token dùng chung cho các scope đã đồng ý; scope chưa đồng ý thì chạy lại authorize.
- **Dropbox:** tick scope trong App Console rồi đăng nhập lại.

## Health check account

Kiểm tra 5 tầng theo thứ tự, dừng ở tầng lỗi đầu tiên; lỗi mạng không bao giờ đẩy account sang `needsReauth`.

1. **Có token:** refresh token có trong Keychain.
2. **Refresh được:** gọi token endpoint; `invalid_grant` → `needsReauth`.
3. **Gọi API được:** Google `about.get?fields=user,storageQuota`, Microsoft `GET /me/drive`, Dropbox `users/get_space_usage`.
4. **Scope đủ:** so scope đang cần với `grantedScopes`; thiếu → `needsConsent`.
5. **Cảnh báo sớm:** quota trên 90%, client secret còn dưới 30 ngày.

| Trạng thái | Điều kiện | Hành động |
| --- | --- | --- |
| healthy | Qua cả 5 tầng | Không làm gì |
| degraded | Quota > 90%, secret < 30 ngày, phản hồi chậm | Badge vàng trên menu bar |
| needsConsent | Thiếu scope | Nút cấp thêm quyền |
| needsReauth | `invalid_grant` | Thông báo + nút đăng nhập lại 1 chạm |
| unreachable | Lỗi mạng hoặc 5xx | Retry backoff |

Khi nào chạy: lúc mở app và khi máy thức dậy; định kỳ mỗi 6 giờ; trước mỗi lần dùng token cho tác vụ lớn; khi gọi tay (nút "Check now", `keyloft health`).

## Chuẩn tuân theo

Thiết kế theo OAuth 2.1 (bản nháp) ngay từ đầu: bắt buộc PKCE, không dùng luồng implicit hay password.

| Chuẩn | Áp dụng | Giai đoạn |
| --- | --- | --- |
| RFC 6749 OAuth 2.0, RFC 6750 Bearer | Toàn bộ TokenVault | 1 |
| RFC 7636 PKCE | Bắt buộc cho app native | 1 |
| RFC 8252 OAuth cho Native Apps | Trình duyệt hệ thống, redirect loopback | 1 |
| RFC 9700 Security BCP | Checklist: `state`, exact redirect, xoay vòng token | 1 |
| OpenID Connect Core + Discovery | `sub` làm định danh; tự đọc endpoint từ `/.well-known/openid-configuration` | 1 |
| RFC 7009 Revocation | Thu hồi Credential | 1 |
| RFC 9207 tham số `iss` | Chống nhầm provider khi có nhiều provider | 1 |
| RFC 8628 Device Authorization Grant | `keyloft login` trên máy không có trình duyệt | Sau |
| RFC 8693 Token Exchange, RFC 8707 Resource Indicators | Cấp token hẹp cho module | 2 |
| Apple LocalAuthentication, Keychain `.userPresence`, Secure Enclave | Mở khóa Vault bằng Touch ID | 1 |
| XPC code signing requirement, `LOCAL_PEERCRED` | Xác thực process gọi Access API | 2 |
| git credential helper, AWS `credential_process` | Export kiểu reference | 3 |
| OWASP MASVS, ASVS | Checklist review bảo mật | Mọi giai đoạn |

## Cấu trúc thư mục

Swift Package Manager, mỗi module một target; giai đoạn 1 chỉ cần các target đánh dấu `(1)`.

```
keyloft/
├── Package.swift
├── App/                      # SwiftUI + menu bar (1)
│   ├── KeyloftApp.swift
│   └── Features/
│       ├── Accounts/         # thêm account, OAuth, trạng thái (1)
│       ├── Providers/        # OAuth client theo provider (1)
│       ├── Secrets/          # (1)
│       ├── Health/           # (1)
│       ├── Audit/            # (1)
│       ├── Modules/          # (2)
│       └── Exports/          # (3)
├── Sources/
│   ├── VaultDomain/          # entity + protocol, không phụ thuộc gì (1)
│   ├── VaultPersistence/     # GRDB, migration, repository (1)
│   ├── SecretVault/          # Keychain, SecAccessControl, LAContext (1)
│   ├── TokenVault/           # PKCE, loopback, refresh, cache (1)
│   ├── Providers/            # Google, Microsoft, Dropbox + quirks (1)
│   ├── HealthCheck/          # (1)
│   ├── KeyloftCLI/           # `keyloft` (1: health, token)
│   ├── ModuleHost/           # (2)
│   ├── AccessAPI/            # (2)
│   ├── MCPServer/            # (2)
│   ├── Exporters/            # (3)
│   └── Modules/StorageModule # (4)
└── Tests/                    # một thư mục test mỗi target, Swift Testing
```

Quy tắc phụ thuộc (SPM ép khi build):

1. `VaultDomain` là gốc, không phụ thuộc target nào.
2. `TokenVault` phụ thuộc `SecretVault`, không có chiều ngược lại.
3. Module (như `StorageModule`) chỉ import `VaultDomain`, không import `TokenVault` hay `SecretVault`.
4. `App`, `KeyloftCLI`, `MCPServer` là các đầu vào, cùng dùng package core.

## Giai đoạn 3: Export config cho app khác

Ghi lại thiết kế đã bàn, chưa làm ở giai đoạn 1.

### Xung đột refresh token

Mỗi lần export phải cấp một Credential riêng, không dùng chung token với Vault.

- **Vấn đề:** Microsoft (và đôi khi Dropbox) xoay vòng refresh token. Nếu app khác dùng chung token, mỗi lần nó refresh sẽ vô hiệu hóa token trong Vault, hoặc ngược lại.
- **Cách sửa:** OAuth lại để ra grant mới (cùng client). Google cho tới 100 refresh token cho mỗi cặp client/user. Mỗi app có token riêng và thu hồi được độc lập.

### Ba chế độ export

Ưu tiên exec, chỉ dùng full value khi app không gọi được lệnh ngoài.

| Chế độ | Cách hoạt động | Khi nào dùng |
| --- | --- | --- |
| Exec (an toàn nhất) | `keyloft run --account gdrive-a -- rclone ls gd:` bơm token qua biến môi trường như `RCLONE_CONFIG_GD_TOKEN`, không ghi ra file | CLI, script, rclone. Giống `op run` hay `doppler run` |
| Reference | File config chứa lệnh gọi Vault thay vì token, ví dụ `"command": "keyloft token gdrive-a"` | App hỗ trợ credential process (kiểu AWS), MCP config |
| Full value | File chứa đủ client ID, client secret và refresh token | App bên thứ ba không gọi được lệnh ngoài |

Chế độ full value bắt buộc Touch ID, cảnh báo, Credential riêng và ghi AuditEvent.

### Định dạng export

Mỗi định dạng là một `Exporter` (protocol), nên thêm định dạng mới không phải sửa core. Thứ tự ưu tiên:

1. **`rclone.conf`**: một section cho mỗi Account.
2. **`.env` / dotenv**: `GOOGLE_CLIENT_ID`, `..._REFRESH_TOKEN`, tên biến tùy chỉnh được.
3. **Google ADC `authorized_user` JSON**: SDK Google đọc qua `GOOGLE_APPLICATION_CREDENTIALS`.
4. **MCP client config**: đoạn `mcpServers` cho Claude Desktop hoặc Claude Code, trỏ vào MCP server của Vault.
5. **JSON chung**: schema riêng để script tự đọc.

### Thực thể export

Thêm 2 thực thể; mỗi ExportRecord gắn với đúng một Credential riêng (`ExportRecord 1—1 Credential`).

| Thực thể | Trường chính |
| --- | --- |
| ExportProfile | `id`, `name`, `format`, `mode` (exec, reference, value), `accountIds`, `variableMapping` |
| ExportRecord | `id`, `profileId`, `credentialId`, `exportedAt`, `destinationHint`, `revokedAt` |

Thu hồi một bản export chỉ ảnh hưởng đến đúng app đó. Vì vậy Credential phải tách khỏi Account: một Account có nhiều Credential (Vault, mỗi bản export, mỗi ApiClient).

## Bước tiếp theo

- [x] Đã chốt tên Keyloft (thay `CloudVault`, dùng làm Keychain prefix)
- [ ] Chuyển app OAuth Google sang In production
- [ ] Chốt scope Google ban đầu: `drive` + `openid email`
- [ ] Dựng khung SPM: `VaultDomain`, `SecretVault`, `TokenVault`, `Providers`
