# SPEC-010: VaultRuntime và CLI — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

Lắp ráp runtime, tích hợp trên GRDB thật, CLI parse/format/exit code.

## Test Environment

- `swift test --filter VaultRuntimeTests`: `RuntimeDependencies` với `VaultDatabase.inMemory()`,
  `InMemorySecretStore`, `StubHTTPClient` (token endpoint + probe URL của 3 provider),
  `FakeBrowserSession` (GET tới loopback thật), `FixedDateProvider`.
- `swift test --filter KeyloftCLITests`: runtime như trên qua `Keyloft.makeRuntime`; `StandardStreams`
  ghi vào buffer.

## Unit Tests (KeyloftCLITests)

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Selector UUID đầy đủ / tiền tố 4 / tiền tố 3 | `AccountSelector` | ok / ok / `notFound` (tiền tố < 4 không hợp lệ) |
| U2 | Selector email hoa thường | `A@x.com` vs `a@X.com` | khớp |
| U3 | Selector mơ hồ | 2 account cùng email khác provider, query email | `.ambiguous` 2 phần tử; `google:a@x.com` → ok |
| U4 | Exit code từng status | `KeyloftExitCode.from` | đúng bảng PRODUCT |
| U5 | worst | `[healthy, unreachable, needsConsent]` | needsConsent (3) |
| U6 | `token` stdout | runtime có account healthy | stdout == `"<token>\n"`; stderr rỗng; exit 0 |
| U7 | `token` audit | — | audit `token.issued` actor cli, trước khi in |
| U8 | `token` needsReauth | stub invalid_grant | stdout rỗng; stderr có gợi ý mở app; exit 2 |
| U9 | `token --force` | token cache còn hạn | 1 request refresh |
| U10 | `health --json` | 2 account | JSON decode được theo DTO; exit theo worst |
| U11 | `accounts` bảng | 3 account | header + 3 dòng, ID 8 ký tự |
| U12 | Chưa có vault | `makeRuntime` throw `vaultNotInitialized` | thông điệp PRODUCT §7; exit 1 |

## Integration Tests (VaultRuntimeTests)

| # | Scenario | Setup | Expected |
|---|----------|-------|----------|
| I1 | Login end-to-end | `runtime.scopes.execute(LoginRequest(newAccount))` Google stub | account healthy trong GRDB; secret trong InMemorySecretStore; `tokens.cachedToken` có (seed) |
| I2 | Health 60 lần | sau I1, `health.check` 60 lần | `healthResults.list(limit: 100).count == 50` |
| I3 | Vòng đời đầy đủ trên GRDB | login → login lại (supersede) → health → token → `removeAccount(ack: true)` | không lỗi FK; DB sạch account; store không còn item; audit có đủ chuỗi action theo thứ tự |

## Edge Cases and Failure Modes

- `RuntimeConfiguration.default(for: .cli, environment: ["KEYLOFT_DEV_LOGIN_KEYCHAIN": "1"])` →
  `useDataProtectionKeychain == false` (U13 thêm vào VaultRuntimeTests).
- stdout đóng (pipe `head -c0`) → không crash.

## Manual Verification

1. App đã ký thêm account → `Keyloft.app/Contents/Helpers/keyloft accounts` thấy account.
2. `rclone lsd gd: --drive-token "{\"access_token\":\"$(keyloft token me@gmail.com)\"}"` hoạt động.
3. `keyloft health; echo $?` khi tắt mạng → 4.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| stdout chỉ có token | U6 |
| Exit code đúng bảng | U4, U5, U8, Manual 3 |
| Account từ app hiện trong CLI | Manual 1 |
| Vòng đời trên GRDB không lỗi FK | I3 |

## Regression Risk

Đổi thứ tự dựng runtime → `onCredentialIssued` không seed. I1 bắt.

## Out of Scope

Cài symlink `/usr/local/bin` (SPEC-011).
