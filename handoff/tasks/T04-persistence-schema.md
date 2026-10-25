# T04: VaultPersistence: VaultDatabase, migration v1, record

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-003](../../specs/SPEC-003-vault-persistence/) | 3 | T03 |

Branch: `task/T04-persistence-schema` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-003 toàn bộ
- SPEC-002 TECH §5 (entity)

## Files (chỉ được tạo/sửa các file này)

- `Sources/VaultPersistence/VaultDatabase.swift`
- `Sources/VaultPersistence/Migrations.swift`
- `Sources/VaultPersistence/Records/*.swift`
- `Sources/VaultPersistence/PersistenceError.swift`
- `Tests/VaultPersistenceTests/DatabaseTests.swift`

## Deliverables

1. `VaultDatabase.open(at:)`, `.inMemory()`, `.defaultURL()` (TECH §2): quyền 0700/0600, WAL, FK on, busy 5 s, phát hiện `schemaTooNew`.
2. Migration `v1_initial` đúng SQL TECH §3, gồm trigger append-only.
3. 6 Record struct ↔ entity (`init(_ entity:)`, `func toEntity() throws -> Entity`), ngày lưu `timeIntervalSince1970`, scope/checks/result là JSON; decode lỗi → `PersistenceError.corruptRow`.

## Tests

SPEC-003 U1, U2, U3, U9, U13 + I1.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter VaultPersistenceTests
```

## Lưu ý

- Kiểm tra API GRDB 7 thật (Sendable của DatabasePool, `databaseDateEncodingStrategy`) — sai so với TECH thì sửa TECH và ghi Deviations.
- Repository chưa làm ở task này (T05, T06) — nhưng U3/U13 cần đọc/ghi: viết qua Record trực tiếp trong test.
- Trước khi code: nêu rõ cách phát hiện schema mới hơn với GRDB `DatabaseMigrator` (vd `appliedIdentifiers` chứa id lạ).

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T04.md` đã viết, BOARD status = `review`
