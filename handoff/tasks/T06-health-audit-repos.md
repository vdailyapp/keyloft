# T06: VaultPersistence: repo HealthCheck (retention 50) + AuditLog

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-003](../../specs/SPEC-003-vault-persistence/) | 4 | T04 |

Branch: `task/T06-health-audit-repos` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-003 TECH §4
- SPEC-003 TESTING U10–U12
- SPEC-002 TECH §6

## Files (chỉ được tạo/sửa các file này)

- `Sources/VaultPersistence/Repositories/GRDBHealthCheckRepository.swift`
- `Sources/VaultPersistence/Repositories/GRDBAuditLog.swift`
- `Tests/VaultPersistenceTests/HealthAuditRepositoryTests.swift`

## Deliverables

1. `GRDBHealthCheckRepository`: `append` trong 1 transaction insert + prune giữ 50 mới nhất theo `checked_at`.
2. `GRDBAuditLog`: chỉ insert; `query` lọc target/actions/since/limit, mới nhất trước.

## Tests

SPEC-003 U10, U11, U12.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter VaultPersistenceTests
```

## Lưu ý

- Song song với T05: không sửa file của T05.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T06.md` đã viết, BOARD status = `review`
