# SPEC-005: Đăng nhập OAuth — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

`TokenVault`: PKCE, authorize URL, scope normalizer, loopback, token endpoint, id_token, login
service. Refresh/cache ở SPEC-006; provider thật ở SPEC-007.

## Test Environment

`swift test --filter TokenVaultTests`. Fake: `StubHTTPClient`, `FakeBrowserSession`,
`FakeCallbackReceiver`, `InMemory*Repository`, `InMemorySecretStore` (qua `SecretVault` thật),
`SeededRandomSource`, `FixedDateProvider`, `SequentialIDGenerator`. ID token test: helper
`TestJWT.make(claims:)` (header `{"alg":"RS256"}`, chữ ký giả `"sig"`) trong TestSupport.
Loopback thật chạy được trong sandbox test (chỉ 127.0.0.1).

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Vector RFC 7636 App. B | `PKCEPair(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")` | `challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"` |
| U2 | Verifier sai độ dài / ký tự | `PKCEPair(verifier:)` 42 ký tự, 129 ký tự, có `+` | throw |
| U3 | generate | `SeededRandomSource` | verifier 43 ký tự `[A-Za-z0-9-._~]`; 2 seed khác → khác |
| U4 | State | `OAuthState.generate` | 43 ký tự base64url, không `=` |
| U5 | constantTimeEquals | "abc"/"abc", "abc"/"abd", "abc"/"ab" | true, false, false |
| U6 | URL đủ tham số, thứ tự cố định | Google provider, scope `openid email drive` | Chuỗi query đúng bằng chuỗi kỳ vọng trong test (gồm `access_type=offline`, `prompt=consent`) |
| U7 | Percent-encode | redirect `http://127.0.0.1:5000/callback`, scope có `/` và `:` | `redirect_uri=http%3A%2F%2F127.0.0.1%3A5000%2Fcallback`, space `%20` |
| U8 | include_granted_scopes | bật cờ | có `include_granted_scopes=true`; tắt → không có |
| U9 | extraAuthParams cố ghi đè `state` | provider giả có `extraAuthParams["state"]` | throw `invariantViolated` |
| U10 | Normalizer Google alias | requested `openid email`, response `"openid https://www.googleapis.com/auth/userinfo.email"` | granted == canonical(requested); denied rỗng |
| U11 | Normalizer MS unechoed + nil scope | requested `openid offline_access Files.Read`, response `"Files.Read openid"`; response nil | granted chứa `offline_access`; nil → granted == requested |
| U12 | Loopback cổng ngẫu nhiên | `configuredRedirect` không port, `start()` | URL `http://127.0.0.1:<p>/callback`, p > 0 |
| U13 | Callback hợp lệ | GET `/callback?code=c&state=s&iss=i` | `CallbackParameters(code:c,state:s,iss:i)`; response 302 `Location: app.vdaily.keyloft://oauth-complete` |
| U14 | Path lạ trước | GET `/favicon.ico` rồi `/callback?...` | lần 1 nhận 404, vẫn chờ; lần 2 hoàn tất |
| U15 | Method khác / request > 8 KB | POST; header 9 KB | 405; 400; vẫn chờ |
| U16 | Timeout & stop | timeout 0.2 s; stop khi đang chờ | `.timeout`; `.cancelled`; port được giải phóng (bind lại được) |
| U17 | Body exchange | stub ghi request | `grant_type=authorization_code&code=…&redirect_uri=…&code_verifier=…&client_id=…`; Content-Type form |
| U18 | client_secret_post vs basic | 2 method | post: có `client_secret` trong body; basic: header `Basic` đúng RFC 6749 §2.3.1 (id có `:` được encode), body không có secret |
| U19 | Refresh body + scope | `refresh(scopes: [a,b])` | `grant_type=refresh_token`, `scope=a+b` |
| U20 | invalid_grant | 400 `{"error":"invalid_grant","error_description":"revoked"}` | `.invalidGrant("revoked")` |
| U21 | invalid_client / invalid_scope / lạ | 401/400 | đúng case; mã lạ → `.other(code:)` |
| U22 | 5xx | 503 | `.server(status: 503)`, `isTransient == true` |
| U23 | Network | stub throw `URLError(.notConnectedToInternet)` | `.network(.notConnectedToInternet)`, `isTransient` |
| U24 | 4xx không JSON / 2xx thiếu access_token | HTML 400; `{}` | `.malformedResponse` |
| U25 | Revoke 3 kiểu | rfc7009, dropboxAPI, unsupported | form `token`+`token_type_hint`; header Bearer; throw `.revocationUnsupported` |
| U26 | TokenResponse không lộ token | `String(describing:)` | không chứa access/refresh token |
| U27 | Decode aud string & array | 2 JWT | `aud` đều là mảng |
| U28 | JWT hỏng | 2 phần; base64 sai; `alg: none` | `.invalidIDToken` |
| U29 | aud không chứa clientId | — | throw |
| U30 | exp quá hạn ngoài leeway | exp = now − 301 | throw; now − 299 → ok |
| U31 | iss Google sai | `https://evil.example` | throw |
| U32 | iss Microsoft template | tid `T`, iss `https://login.microsoftonline.com/T/v2.0` | ok; tid khác → throw; thiếu tid → throw |
| U33 | Happy path account mới | FakeCallbackReceiver code+state echo, stub token đủ | `isNewAccount`, account `healthy`, 1 credential active, 1 secret refreshToken, audit `account.added`,`credential.issued`,`scope.granted` |
| U34 | State sai | callback state khác | `.stateMismatch`; `StubHTTPClient.requests` không có token URL; audit failure; không account/secret |
| U35 | iss sai / thiếu khi bắt buộc | quirks `authorizationResponseIssSupported = true` | `.issuerMismatch`; 0 request token |
| U36 | access_denied | callback `error=access_denied` | `.accessDenied`; không ghi gì |
| U37 | Thiếu refresh token | response không `refresh_token` | `.missingRefreshToken`; không secret |
| U38 | Scope bị bỏ tick | xin `openid email drive`, cấp `openid email` | account `needsConsent`; `deniedScopes == [drive]`; audit `scope.denied` scopes `[drive]` |
| U39 | Đăng nhập lại cùng sub (newAccount) | login 2 lần cùng sub | 1 account, 2 credential; c1 `superseded` by c2; audit `credential.superseded` |
| U40 | Re-auth sai account | `.existing(A)`, sub khác | `.accountMismatch`; account A không đổi; 0 secret mới (lỗi xảy ra trước bước 12) |
| U41 | Lỗi sau khi tạo secret → bồi hoàn | credentials repo fake throw khi insert | throw; `InMemorySecretStore` không còn item mới; metadata secret bị xóa |
| U42 | Người dùng hủy trình duyệt | FakeBrowserSession `.cancel` | `.userCancelled`; receiver `stop()` được gọi |
| U43 | Browser trả về trước callback | browser return ngay, callback tới sau 50 ms | vẫn thành công |
| U44 | Client secret từ SecretVault | client có `clientSecretRef` | body/header chứa secret đó; `secretRead` không audit (actor .app) |
| U45 | Observer seed token | `onCredentialIssued` | gọi 1 lần với accountId, expiresAt = now + expires_in |

## Integration Tests

| # | Scenario | Setup | Expected |
|---|----------|-------|----------|
| I1 | Loopback + FakeBrowserSession thật | `LoopbackServer` thật; FakeBrowserSession GET tới redirect | params đúng; listener đóng sau callback (connect lại bị từ chối) |
| I2 | Login end-to-end không mạng ngoài | `OAuthLoginService` + `LoopbackServer` thật + FakeBrowserSession + StubHTTPClient | `LoginOutcome` đúng như U33; redirect_uri gửi lúc exchange == redirect thật có port |

## Edge Cases and Failure Modes

- Hai login chạy song song cho cùng client: hai loopback cổng khác nhau, hai state khác nhau,
  không lẫn callback (I2 chạy 2 lần đồng thời).
- `expires_in` thiếu → AccessToken expiresAt = now + 3600 (U45 biến thể).
- Email thay đổi giữa 2 lần login cùng sub → account cập nhật email, không tạo account mới.

## Manual Verification

1. (Sau SPEC-011) Thêm account Google thật; trong màn consent bỏ tick Drive → app hiện cảnh báo thiếu
   quyền `drive`.
2. Đóng tab trình duyệt giữa chừng → app hiện "Đã hủy đăng nhập" trong ≤ 2 s (ASWebAuthenticationSession).
3. `lsof -iTCP -sTCP:LISTEN | grep keyloft` sau khi xong → không còn cổng mở.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| S256 + state ≥ 43 ký tự | U3, U4, U6 |
| Loopback chỉ 127.0.0.1, đóng sau callback/5 phút | U12, U16, I1, Manual 3 |
| State sai → 0 request token | U34 |
| Bỏ tick → grantedScopes thiếu đúng, scope.denied, needsConsent | U10, U11, U38, Manual 1 |
| Login lại cùng sub → không trùng account, credential cũ superseded | U39 |
| 3 provider thật | T29 manual |

## Regression Risk

Đổi thứ tự query trong `AuthorizationRequest.url()` làm U6 fail — chủ ý (phát hiện thay đổi
tham số gửi lên provider).

## Out of Scope

Chữ ký JWT; RFC 8628.
