# Specs — Keyloft giai đoạn 1 (OAuth core)

Spec tổng: [`docs/PROJECT-SPEC.md`](../docs/PROJECT-SPEC.md). Mỗi spec là một thư mục
`SPEC-NNN-slug/` gồm:

- `PRODUCT.md` — người dùng nhận được gì, tiêu chí thành công (đọc trước).
- `TECH.md` — interface, type, luồng, các bước implement (đọc thứ hai).
- `TESTING.md` — case test có ID (`U1`, `I1`), map với tiêu chí thành công.

Code đánh số tuần tự, không tái dùng. Commit/PR ghi mã spec + task: `SPEC-005/T12: loopback server`.
Kiểm tra cấu trúc: `python3 <spec-skill>/scripts/spec.py validate --all` (đọc `.spec-config`).

| Spec | Target | Nội dung | Phụ thuộc spec |
| --- | --- | --- | --- |
| [SPEC-001](SPEC-001-spm-skeleton/) | `Package.swift`, CI | Khung SPM, target, lint, CI, TestSupport | — |
| [SPEC-002](SPEC-002-vault-domain/) | `VaultDomain` | Entity, ID, ScopeSet, protocol repository/infra | 001 |
| [SPEC-003](SPEC-003-vault-persistence/) | `VaultPersistence` | GRDB, migration v1, repository | 002 |
| [SPEC-004](SPEC-004-secret-vault/) | `SecretVault` | Keychain, `.userPresence`, LAContext, facade | 002 |
| [SPEC-005](SPEC-005-oauth-login/) | `TokenVault` | PKCE, loopback, authorize, exchange, id_token, login service | 002, 004 |
| [SPEC-006](SPEC-006-token-refresh-cache/) | `TokenVault` | Refresh, xoay vòng RT, cache RAM, single-flight | 005 |
| [SPEC-007](SPEC-007-providers/) | `Providers` | Google/Microsoft/Dropbox, quirks, discovery, API probe | 002 |
| [SPEC-008](SPEC-008-health-check/) | `HealthCheck` | 5 tầng, map trạng thái, scheduler, backoff | 006, 007 |
| [SPEC-009](SPEC-009-scope-management/) | `TokenVault` | Cấp thêm scope, giảm scope, thu hồi, xóa account | 005, 006 |
| [SPEC-010](SPEC-010-cli-runtime/) | `VaultRuntime`, `KeyloftCLI` | Composition root; `keyloft health`, `keyloft token` | 003–009 |
| [SPEC-011](SPEC-011-macos-app/) | `App/` | Menu bar, các màn hình Features, Touch ID, ký app | 010 |

Việc chia task cho agent: [`handoff/BOARD.md`](../handoff/BOARD.md).
