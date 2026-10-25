# SPEC-009: Quản lý scope, thu hồi, xóa account — Test Plan

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Tech spec:** ./TECH.md
**Last updated:** 2026-10-25

## Scope

`ScopeService`, `SecretVault.purgeValue`. Login thật đã test ở SPEC-005.

## Test Environment

`swift test --filter TokenVaultTests/ScopeServiceTests`. `FakeLoginRunner` (ghi `requests`, trả
`LoginOutcome` dựng sẵn và **thực sự** ghi credential mới vào InMemory repo để mô phỏng);
`StubHTTPClient` đếm request theo URL; `TokenProvider` thật.

## Unit Tests

| # | Case | Covers | Expected |
|---|------|--------|----------|
| U1 | Plan Google | granted `[openid,email]`, default thêm `drive` | `.browser`, scopes `[drive,openid,email]`, `includeGrantedScopes`, `loginHint == email` |
| U2 | Execute Google không revoke | `execute(plan)` | 0 request tới `oauth2.googleapis.com/revoke`; credential cũ superseded |
| U3 | Plan Microsoft / Dropbox / đủ | — | MS scopes = granted ∪ missing; Dropbox `.consoleThenRelogin` URL console; đủ → `.nothingMissing` |
| U4 | Reduce giữ quyền liên tục | reduce `[openid,email]` | Mọi thời điểm (kiểm sau mỗi bước bằng hook FakeLoginRunner) có ≥1 credential active; cuối cùng active = mới |
| U5 | Reduce không phải tập con | to chứa scope lạ | `.notSubset(extra:)`; FakeLoginRunner 0 request |
| U6 | Revoke Google cần ack | ack false | throw `.grantWideRevocationNotAcknowledged`; 0 request |
| U7 | Revoke Google ack | 2 credential (active + superseded) | 1 request revoke với `token_type_hint=refresh_token`; cả 2 `revoked`; account `needsReauth` |
| U8 | Revoke Dropbox | — | refresh rồi POST revoke với Bearer = access token mới; `.revokedRemotely` |
| U9 | Remove account Dropbox | 2 credential, 3 health | revoke 2 lần; account/credential/health = 0; InMemorySecretStore không còn item của account; audit `account.removed` |
| U10 | Remove khi revoke lỗi mạng | stub throw network | vẫn xóa cục bộ; revocations `.localOnly("network")` |
| U11 | Remove Microsoft | — | 0 request mạng; `.localOnly`; dữ liệu cục bộ sạch |
| U12 | Execute: refresh lỗi → không dọn | forceRefresh 503 | secret của credential superseded vẫn còn; `execute` không throw |
| U13 | Execute: refresh ok → dọn | — | secret superseded bị purge; hàng credential còn |
| U14 | `purgeValue` | — | Keychain item mất; metadata còn, `rotatedAt` set; audit `secret.deleted` |

## Integration Tests

Không (end-to-end ở T29 manual).

## Edge Cases and Failure Modes

- Remove account không có credential → chỉ xóa account, không gọi mạng.
- Secret delete lỗi trong remove → `leftoverSecrets` chứa id, account vẫn bị xóa.

## Manual Verification

1. Google thật: account thiếu `drive` → Cấp thêm quyền → consent chỉ hỏi Drive → account healthy.
2. Xóa account Google (ack) → myaccount.google.com/permissions không còn Keyloft.
3. `security find-generic-password -s app.vdaily.keyloft -a refreshToken.<id>` sau khi xóa → not found.

## Success Criteria Coverage

| Criterion (PRODUCT.md) | Proven by |
|------------------------|-----------|
| Google incremental không revoke | U2 |
| Xóa account sạch Keychain + DB | U9, U11, Manual 3 |
| Google revoke cần ack | U6 |
| Reduce luôn có credential dùng được | U4 |

## Regression Risk

Đổi thứ tự xóa (secret trước account) → vi phạm FK RESTRICT ở GRDB (không thấy với InMemory).
Bắt bằng SPEC-010 I3.

## Out of Scope

UI xác nhận (SPEC-011).
