# Security Review — Keyloft giai đoạn 1 (OAuth core + App macOS)

**Ngày:** 2026-10-26 · **Người review (phần tự động):** agent zcode / GLM-5.3-Flash (T29)
**Phạm vi:** code tại commit sau T30 (lint chặn `try?`/`print`/`Date()`), SPEC-005..011.
**Phương pháp:** checklist RFC 9700 / RFC 8252 / RFC 9207 / OIDC / Keychain / OWASP MASVS
(STORAGE, AUTH, NETWORK), mỗi mục đối chiếu trực tiếp trên code thật (file:dòng) hoặc test ID.
Phần cần chạy app thật (Keychain entitlement, Touch ID, trình duyệt) → checklist manual trong
`handoff/reports/T29.md`, cần người ký tên.

**Tổng kết: 26 PASS, 0 FAIL nghiêm trọng, 2 mục PASS-có-ghi-chú** (X1 không có nonce chống
replay id_token; X2 discovery merge tin `codeChallengeMethodsSupported` vắng mặt — xem "Ghi chú
rủi ro còn mở" cuối tài liệu).

## 1. RFC 9700 — OAuth 2.0 Security Best Current Practice

| # | Mục | Kết quả | Bằng chứng |
|---|-----|---------|-----------|
| 1.1 | `state` là giá trị ngẫu nhiên ≥ 128 bit entropy, sinh từ CSPRNG | **PASS** | `Sources/TokenVault/PKCE.swift:33-37` — 32 byte qua `RandomSource` (tiêm `SystemRandomSource` = SecRandom-copy tương đương, `Sources/VaultDomain/Infrastructure.swift`); test tất định dùng `SeededRandomSource`. |
| 1.2 | So `state` constant-time | **PASS** | `Sources/TokenVault/PKCE.swift:46` (`constantTimeEquals`, vòng so byte không dừng sớm); gọi tại `Sources/TokenVault/OAuthLoginService.swift:175` — sai → audit + `OAuthError.stateMismatch`. |
| 1.3 | PKCE S256 bắt buộc; `code_challenge_method` luôn gửi | **PASS** | `Sources/TokenVault/PKCE.swift:9` (`method = "S256"`), `:28` challenge = SHA256 qua CryptoKit; `Sources/TokenVault/AuthorizationRequest.swift:49-55` — luôn gửi `response_type=code` + `code_challenge` + `code_challenge_method`. Test: `Tests/TokenVaultTests/PKCETests.swift` (vector RFC 7636). |
| 1.4 | Verifier chỉ unreserved, đủ dài | **PASS** | `Sources/TokenVault/PKCE.swift:19-26` — 43–128 ký tự, chỉ `[A-Za-z0-9-._~]`. |
| 1.5 | Redirect URI so khớp EXACT, không so prefix | **PASS** | Redirect chỉ đến từ `client.redirectURI` lưu DB (`Sources/TokenVault/OAuthLoginService.swift:110` — `receivers(client.redirectURI)`), loopback chỉ nhận đúng cấu hình đó (`Sources/TokenVault/Loopback/LoopbackServer.swift:46` — `host == "127.0.0.1"`; callback sai redirect → `LoopbackError.invalidRedirect` qua `mapLoopbackError`). UI chặn redirect lạ khi nhập client: `App/Features/Providers/OAuthClientsModel.swift:38-44` (chỉ `http://127.0.0.1/callback`). |
| 1.6 | Không implicit flow (`response_type=token`) | **PASS** | `Sources/TokenVault/AuthorizationRequest.swift:49` — chỉ `response_type=code`. Không có đường nào tạo `token` response type. |
| 1.7 | Refresh token xoay vòng khi provider cấp RT mới; lưu trước khi trả token | **PASS** | `Sources/TokenVault/TokenProvider.swift:166-186` — rotate với retry 3 lần, persist fail → `needsReauth` + `rotationPersistFailed`. Test: SPEC-006 U6–U8. |
| 1.8 | Lỗi mạng/5xx KHÔNG đổi trạng thái account sang needsReauth | **PASS** | `Sources/TokenVault/TokenProvider.swift:155-156` — default: throw `.oauth` không đổi status, không audit; property test SPEC-006 "100 vòng lỗi tạm thời — không bao giờ needsReauth". |
| 1.9 | `invalid_grant` → needsReauth + xóa cache + audit; lỗi persistence không nuốt | **PASS** | `Sources/TokenVault/TokenProvider.swift:143-149` (T30); test SPEC-006 U10, U15. |
| 1.10 | Token endpoint chỉ gọi qua HTTPS endpoint của provider (không downgrade) | **PASS** | `Sources/Providers/Provider.swift` + fixtures — mọi token/auth/revoke URL đều https (`Tests/KeyloftTestSupport/Fixtures.swift`); URL đến từ catalog/discovery hợp lệ (mục 3). |
| 1.11 | Authorization code chỉ dùng 1 lần, không replay | **PASS** | Mỗi `login()` tạo PKCE/state mới (`OAuthLoginService.swift:115-116`); loopback nhận đúng 1 callback rồi stop (`LoopbackServer.swift:11` — nhận đúng 1 callback hợp lệ; `stop()` chạy trên mọi đường thoát `OAuthLoginService.swift:113-122`). |

## 2. RFC 8252 — OAuth cho Native Apps

| # | Mục | Kết quả | Bằng chứng |
|---|-----|---------|-----------|
| 2.1 | Loopback redirect chỉ `http://127.0.0.1` (không localhost, không 0.0.0.0) | **PASS** | `Sources/TokenVault/Loopback/LoopbackServer.swift:46` (bắt buộc host `127.0.0.1`), `:57` — `NWEndpoint.hostPort(host: "127.0.0.1", port:)`. |
| 2.2 | Listener bind loopback interface, port bất kỳ/port cố định | **PASS** | `LoopbackServer.swift:59-63` — NWListener với `requiredLocalEndpoint`; port cố định lấy từ redirectURI của client (Dropbox). |
| 2.3 | Trình duyệt hệ thống (ASWebAuthenticationSession), không webview nhúng | **PASS** | `App/Platform/WebAuthBrowserSession.swift` — `ASWebAuthenticationSession`; protocol `BrowserSession` tách tầng (`Sources/TokenVault/BrowserSession.swift:10`). |
| 2.4 | Custom scheme riêng cho app + loopback http cho client desktop | **PASS** | Scheme `app.vdaily.keyloft` (`App/Info.plist` CFBundleURLTypes; `OAuthLoginService.swift:149` callbackScheme); loopback cho client có redirect 127.0.0.1. |

## 3. RFC 9207 + OIDC Discovery (chống nhầm provider / discovery giả mạo)

| # | Mục | Kết quả | Bằng chứng |
|---|-----|---------|-----------|
| 3.1 | `iss` trong response có → so khớp provider; bắt buộc khi provider khai báo hỗ trợ | **PASS** | `Sources/TokenVault/OAuthLoginService.swift:182-190`; template tenant (Microsoft) qua pattern `[^/]+` (`:344-354`). Test: OAuthLoginServiceTests (issuerMismatch). |
| 3.2 | Discovery merge an toàn: issuer khác → bỏ doc, giữ giá trị tĩnh | **PASS** | `Sources/Providers/OIDCDiscovery.swift` — `merge` so issuer nguyên chuỗi (template cho MS); S256 thiếu trong doc → bỏ doc. Test: SPEC-007 U-tests (discovery). |
| 3.3 | `sub` là định danh account; account trùng sub không tạo trùng | **PASS** | `Sources/TokenVault/OAuthLoginService.swift:237-255` — tìm theo (provider, client, sub) trước khi tạo; đích `.existing` sai sub → `accountMismatch` (`:229-232`). |

## 4. OIDC ID Token checks

| # | Mục | Kết quả | Bằng chứng |
|---|-----|---------|-----------|
| 4.1 | `aud` phải chứa client_id | **PASS** | `Sources/TokenVault/IDToken.swift:109-111`. |
| 4.2 | `exp` hết hạn (leeway 300 s) → từ chối | **PASS** | `Sources/TokenVault/IDToken.swift:112-114`. |
| 4.3 | `iss` khớp issuer (template tenant cho Microsoft) | **PASS** | `Sources/TokenVault/IDToken.swift:115-127`; thiếu `tid` → từ chối. |
| 4.4 | alg `none` bị từ chối; JWT hỏng → lỗi rõ ràng | **PASS** | `Sources/TokenVault/IDToken.swift:86-88` (alg none → `invalidIDToken`); header/payload hỏng → từ chối (`:79-92`). |
| 4.5 | Chữ ký id_token KHÔNG được kiểm (không có JWKS) | **PASS-có-ghi-chú (X1)** | Chỉ decode claims, không verify chữ ký và không có `nonce` — chấp nhận được cho luồng code + `iss` RFC 9207 vì code trao đổi trực tiếp với token endpoint của provider qua TLS (đáp ứng OIDC Core §3.1.3.7 cho native app không JWKS), nhưng ghi vào rủi ro còn mở. Thiếu nonce không phải lỗi RFC 9700 (nonce là yêu cầu của implicit/hybrid, không phải code flow). |
| 4.6 | id_token thiếu → từ chối login | **PASS** | `Sources/TokenVault/OAuthLoginService.swift:210-212` — `missingIDToken`. |

## 5. Keychain (Apple) — lưu refresh token / client secret

| # | Mục | Kết quả | Bằng chứng |
|---|-----|---------|-----------|
| 5.1 | Service prefix riêng `app.vdaily.keyloft`; không synchronizable (iCloud sync tắt) | **PASS** | `Sources/SecretVault/KeychainQuery.swift:10-12` (`kSecAttrSynchronizable: false`); service từ `KeychainConfiguration.service` (`"<TEAMID>.app.vdaily.keyloft"` khi ký — `KeychainSecretStore.swift:8`). |
| 5.2 | Accessibility: ThisDeviceOnly; secret người nhập gắn Touch ID (AccessControl) | **PASS** | `Sources/SecretVault/KeychainSecretStore.swift:54` (`AfterFirstUnlockThisDeviceOnly`), `:59-64` (`WhenUnlockedThisDeviceOnly` + `.userPresence` access control cho `requiresUserPresence`). Test: SPEC-004 U-tests + `make test-keychain`. |
| 5.3 | Đọc secret người nhập cần `AuthenticatedContext` từ VaultLock (Touch ID 5 phút) | **PASS** | `Sources/SecretVault/VaultLock.swift:90-94` (`currentContext` nil khi locked/quá hạn); `VaultLock.swift:30` reuseDuration = 300 s; KeychainSecretStore dùng context đó khi presence. Test: SPEC-004 U11–U14. |
| 5.4 | SQLite KHÔNG chứa giá trị secret — chỉ `keychainRef` (SecretID) | **PASS** | `Sources/VaultDomain/Credential.swift:7` (`refreshTokenRef: SecretID`); `OAuthClient.clientSecretRef: SecretID?` (`Sources/VaultDomain/OAuthClient.swift:8`). Value chỉ đi qua `SecretVault` (`Sources/SecretVault/SecretVault.swift:6-8` doc). |
| 5.5 | Access token chỉ trong RAM (cache actor), không ghi đĩa | **PASS** | `Sources/TokenVault/TokenProvider.swift:24` (`cache: [AccountID: AccessToken]` trong actor — không persist); không có đường ghi token ra DB/file. |

## 6. Lưu trữ cục bộ — OWASP MASVS-STORAGE

| # | Mục | Kết quả | Bằng chứng |
|---|-----|---------|-----------|
| 6.1 | DB file 0600, thư mục 0700, WAL + SHM 0600; chmod lỗi → throw (không mở với quyền rộng) | **PASS** | `Sources/VaultPersistence/VaultDatabase.swift:20,28` (0700), `:46,52-58` (0600 DB + `-wal` + `-shm`, lỗi → `PersistenceError.database`). Test: SPEC-003 U1, U14, U15. |
| 6.2 | Clipboard tự xóa sau 60 s nếu chưa bị copy đè | **PASS** | `App/Platform/Clipboard.swift:7` (`autoClearInterval = 60`), `:24-33` (changeCount guard). |
| 6.3 | Giá trị secret không nằm trong state UI lâu hơn cần thiết | **PASS** | `App/Features/Providers/OAuthClientForm.swift:118-121` (xóa SecureField ngay sau lưu), `App/Features/Secrets/SecretsModel.swift:41-47` (reveal 30 s, xóa khi khóa); test U10 (Mirror không chứa secret), U14. |
| 6.4 | Notification/userInfo không chứa secret | **PASS** | `App/Platform/Notifier.swift:36-38` — chỉ accountId; nội dung email + trạng thái. |
| 6.5 | Audit log không chứa giá trị token | **PASS** | Mọi `appendAudit` chỉ ghi target/scope/result; `result.failure(reason:)` chỉ chuỗi mô tả lỗi (mô tả các enum lỗi không chứa giá trị — mục 7). |

## 7. Log & description — không lộ secret

| # | Mục | Kết quả | Bằng chứng |
|---|-----|---------|-----------|
| 7.1 | Không `print(` trong Sources/App (trừ CLI qua StandardStreams) | **PASS** | `scripts/lint-rules.sh` (T30) chặn trong `make lint`; 0 vi phạm. |
| 7.2 | `description` của type chứa secret phải che | **PASS** | `Sources/VaultDomain/AccessToken.swift:19` — `AccessToken(<redacted>)`; `Sources/TokenVault/TokenEndpointClient.swift:22-25` — TokenResponse che access/refresh/id token. |
| 7.3 | Lỗi Keychain không kèm giá trị (chỉ OSStatus/enum) | **PASS** | `Sources/SecretVault/SecretStoreError` — case `osStatus(Int)`/`authFailed`/... không mang dữ liệu; `SecretVaultError.store(error)` bọc enum. |
| 7.4 | Lỗi 网络 bọc thành OAuthError không kèm payload | **PASS** | `Sources/TokenVault/TokenEndpointClient.swift:169-175` — URLError → `.network(code)`; body lỗi chỉ decode trường `error`/`error_description` chuẩn RFC. |
| 7.5 | Không log Date()/UUID trực tiếp trong logic (tái phạm bị chặn) | **PASS** | `scripts/lint-rules.sh` rule 3 trong `make lint`. |

## 8. OWASP MASVS-AUTH (luồng xác thực)

| # | Mục | Kết quả | Bằng chứng |
|---|-----|---------|-----------|
| 8.1 | Thu hồi credential: chỉ `finalizeRevocation` khi revoke provider thành công; thất bại → giữ secret + audit `.failure` (retry được) | **PASS** | `Sources/TokenVault/ScopeService.swift:154-170` (T30); test SPEC-009 U15. |
| 8.2 | Thu hồi Google grant-wide cần xác nhận tường minh (ack) | **PASS** | `Sources/TokenVault/ScopeService.swift:177-181,207-209`; UI chặn: `App/Features/Accounts/AccountsModel.swift` (pendingConfirmation), test U7. |
| 8.3 | State/PKCE không tái sử dụng giữa các login (mỗi login sinh mới) | **PASS** | `OAuthLoginService.swift:115-116` — generate mỗi `login()`; loopback receiver tạo mới mỗi lần. |
| 8.4 | Account đích `.existing` phải khớp `sub` (chống tráo account) | **PASS** | `OAuthLoginService.swift:229-232` — `accountMismatch`. |
| 8.5 | Vault khóa khi máy ngủ/khóa màn hình; Secrets không render khi khóa | **PASS** | `App/AppContainer.swift:52-59` (SystemEvents onLock → lock()); `App/Features/Secrets/SecretsModel.swift` (apply(.locked) xóa rows+revealed); test U12, U13. |

## 9. OWASP MASVS-NETWORK

| # | Mục | Kết quả | Bằng chứng |
|---|-----|---------|-----------|
| 9.1 | Mọi gọi mạng qua `HTTPClient` abstraction; không URLSession trực tiếp rải rác | **PASS** | `Sources/TokenVault/URLSessionHTTPClient.swift` là impl duy nhất; dựng tại composition root `Sources/VaultRuntime/VaultRuntime.swift:178`. |
| 9.2 | URLSession ephemeral (không dùng cookie/cache toàn cục) | **PASS** | `Sources/VaultRuntime/VaultRuntime.swift:162` (doc) + `URLSessionHTTPClient` — `.ephemeral`. |
| 9.3 | Endpoint provider là HTTPS; discovery issuer phải khớp trước khi áp | **PASS** | Mục 1.10, 3.2. ATS của macOS chặn http thường (chỉ loopback 127.0.0.1 được dùng cho callback). |
| 9.4 | Loopback server chỉ nhận 1 callback rồi stop; sai redirect/param → lỗi, không treo | **PASS** | `LoopbackServer.swift:11,46`; `OAuthLoginService.swift:113-122` — `stop()` trên mọi đường thoát. Test: `LoopbackServerTests`. |

## Ghi chú rủi ro còn mở (không phải FAIL, theo dõi)

1. **X1 — id_token chưa verify chữ ký (không JWKS) và không có nonce.** Đáp ứng OIDC Core cho
   code flow khi code trao đổi trực tiếp với provider qua TLS; nếu giai đoạn 2 thêm luồng lấy
   id_token từ nơi khác thì bắt buộc thêm JWKS verify + nonce.
2. **X2 — Discovery**: nếu doc không có trường `codeChallengeMethodsSupported`, merge vẫn áp
   (giữ tĩnh là an toàn hơn nhưng làm mất lợi ích discovery). Đã giới hạn: issuer phải khớp
   nguyên chuỗi và S256 xuất hiện thì phải có S256.
3. **Keychain thật + CLI chung access group** chưa chứng minh bằng tự động — nằm ở checklist
   manual (SPEC-010 Manual 1, SPEC-011 Manual 10): cần người chạy app đã ký + CLI embed tại
   `Keyloft.app/Contents/Helpers/keyloft`.
