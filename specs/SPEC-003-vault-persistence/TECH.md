# SPEC-003: VaultPersistence — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

Cần schema ổn định ngay từ v1 vì CLI và app dùng chung file. GRDB 7 hỗ trợ Swift 6 concurrency
(`DatabasePool` là `Sendable`, có API `async`).

## Relevant Code

- `Sources/VaultDomain/Repositories.swift` — protocol cần implement (SPEC-002 §6)
- `Sources/VaultDomain/*.swift` — entity

## Current State

Placeholder `Sources/VaultPersistence/VaultPersistence.swift`.

## Proposed Changes

### 1. File layout

```
Sources/VaultPersistence/
├── VaultDatabase.swift            # mở DB, cấu hình, migrator
├── Migrations.swift               # v1
├── Records/                       # struct *Record: FetchableRecord, PersistableRecord <-> entity
│   ├── OAuthClientRecord.swift
│   ├── AccountRecord.swift
│   ├── CredentialRecord.swift
│   ├── SecretRecord.swift
│   ├── HealthCheckRecord.swift
│   └── AuditEventRecord.swift
├── Repositories/
│   ├── GRDBOAuthClientRepository.swift
│   ├── GRDBAccountRepository.swift
│   ├── GRDBCredentialRepository.swift
│   ├── GRDBSecretMetadataRepository.swift
│   ├── GRDBHealthCheckRepository.swift
│   └── GRDBAuditLog.swift
└── PersistenceError.swift
```

Record tách khỏi entity: entity trong `VaultDomain` không biết GRDB.

### 2. VaultDatabase

```swift
public final class VaultDatabase: Sendable {
    public let writer: any DatabaseWriter               // DatabasePool (file) hoặc DatabaseQueue (memory)
    public static func defaultURL() throws -> URL       // ~/Library/Application Support/app.vdaily.keyloft/vault.sqlite
    public static func open(at url: URL) throws -> VaultDatabase   // tạo thư mục 0700, file 0600, WAL, migrate
    public static func inMemory() throws -> VaultDatabase          // cho test
}
```

Cấu hình (`Configuration`): `foreignKeysEnabled = true`, `busyMode = .timeout(5)`,
`prepareDatabase { try $0.execute(sql: "PRAGMA journal_mode = WAL") }` (chỉ với pool).
Trước migrate: nếu `migrator.hasBeenSuperseded` / có migration lạ không biết → throw
`PersistenceError.schemaTooNew`.

### 3. Migration v1 (`"v1_initial"`)

Cột thời gian: `DOUBLE` (timeIntervalSince1970) — GRDB mặc định lưu `Date` dạng text; dùng
`databaseDateEncodingStrategy = .timeIntervalSince1970` trên mọi record cho so sánh/sắp xếp đúng.
Scope: `TEXT` chứa JSON array đã sắp xếp (SPEC-002 Codable của `ScopeSet`).

```sql
CREATE TABLE oauth_client (
  id TEXT PRIMARY KEY NOT NULL,
  provider_id TEXT NOT NULL,
  client_id TEXT NOT NULL,
  client_secret_ref TEXT REFERENCES secret(id) ON DELETE SET NULL,
  redirect_uri TEXT NOT NULL,
  secret_expires_at DOUBLE,
  label TEXT NOT NULL,
  created_at DOUBLE NOT NULL
);
CREATE TABLE account (
  id TEXT PRIMARY KEY NOT NULL,
  provider_id TEXT NOT NULL,
  oauth_client_id TEXT NOT NULL REFERENCES oauth_client(id) ON DELETE RESTRICT,
  external_id TEXT NOT NULL,
  email TEXT, display_name TEXT,
  status TEXT NOT NULL,
  status_changed_at DOUBLE NOT NULL,
  created_at DOUBLE NOT NULL,
  UNIQUE (provider_id, oauth_client_id, external_id)
);
CREATE TABLE credential (
  id TEXT PRIMARY KEY NOT NULL,
  account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  refresh_token_ref TEXT NOT NULL REFERENCES secret(id) ON DELETE RESTRICT,
  requested_scopes TEXT NOT NULL,
  granted_scopes TEXT NOT NULL,
  issued_at DOUBLE NOT NULL,
  superseded_by TEXT REFERENCES credential(id) ON DELETE SET NULL,
  status TEXT NOT NULL
);
CREATE INDEX credential_account ON credential(account_id, status, issued_at);
CREATE TABLE secret (
  id TEXT PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL,
  label TEXT NOT NULL,
  keychain_account TEXT NOT NULL UNIQUE,     -- KeychainRef.account
  requires_user_presence INTEGER NOT NULL,
  created_at DOUBLE NOT NULL,
  rotated_at DOUBLE
);
CREATE TABLE health_check_result (
  id TEXT PRIMARY KEY NOT NULL,
  account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  checked_at DOUBLE NOT NULL,
  status TEXT NOT NULL,
  checks TEXT NOT NULL                       -- JSON [HealthCheckItem]
);
CREATE INDEX health_account_time ON health_check_result(account_id, checked_at DESC);
CREATE TABLE audit_event (
  id TEXT PRIMARY KEY NOT NULL,
  actor TEXT NOT NULL, action TEXT NOT NULL, target TEXT NOT NULL,
  scopes TEXT, result TEXT NOT NULL,         -- JSON AuditResult
  timestamp DOUBLE NOT NULL
);
CREATE INDEX audit_time ON audit_event(timestamp DESC);
CREATE INDEX audit_target ON audit_event(target, timestamp DESC);
CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_event BEGIN SELECT RAISE(ABORT, 'audit_event is append-only'); END;
CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_event BEGIN SELECT RAISE(ABORT, 'audit_event is append-only'); END;
```

Ghi chú: `credential.refresh_token_ref ON DELETE RESTRICT` — service phải xóa credential trước rồi
mới xóa secret (SPEC-009 xử lý thứ tự).

### 4. Repository

- Mỗi repo: `public struct GRDBXxxRepository: XxxRepository { let db: VaultDatabase }`.
  Dùng `try await db.writer.write { ... }` / `read { ... }`.
- `GRDBOAuthClientRepository.delete`: đếm account trước, > 0 → `DomainError.hasDependents("oauth_client:<id>")`.
- `GRDBCredentialRepository.active(for:)`: `status = 'active' ORDER BY issued_at DESC LIMIT 1`.
- `markSuperseded(id, by:)`: một transaction, set `status='superseded', superseded_by=?`;
  id không tồn tại → `DomainError.notFound`.
- `GRDBHealthCheckRepository.append`: một transaction: insert, rồi
  `DELETE FROM health_check_result WHERE account_id = ? AND id NOT IN (SELECT id ... ORDER BY checked_at DESC LIMIT 50)`.
- `GRDBAuditLog`: chỉ `insert`; `query` build SQL có điều kiện theo `AuditQuery`.
- Lỗi GRDB → bọc thành `PersistenceError.database(String)` (message), trừ lỗi miền đã nói ở trên.

```swift
public enum PersistenceError: Error, Sendable, Equatable {
    case schemaTooNew
    case database(String)
    case corruptRow(table: String, id: String)   // decode JSON/enum thất bại
}
```

## Implementation Steps

1. **T04 (GLM-5.3)** — `VaultDatabase`, `Migrations`, toàn bộ `Records/`, `PersistenceError`.
   Test U1–U3, U9.
2. **T05 (Flash)** — 4 repo: OAuthClient, Account, Credential, SecretMetadata. Test U4–U8.
3. **T06 (Flash)** — HealthCheck + AuditLog repo. Test U10–U13.

T05 và T06 chạy song song (không chung file).

## Testing

See ./TESTING.md. Seam: mọi test dùng `VaultDatabase.inMemory()`; test migration/permission dùng
file trong `FileManager.default.temporaryDirectory`.

## Risks and Rollback

- Sai kiểu cột ngày → sắp xếp sai. U3 bắt.

## Open Questions

- Có cần bảng `schema_info` riêng không? Không — GRDB `grdb_migrations` đủ.
