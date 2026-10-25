# T05: VaultPersistence: repo OAuthClient, Account, Credential, SecretMetadata

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-003](../../specs/SPEC-003-vault-persistence/) | 4 | T04 |

Branch: `task/T05-core-repos` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-003 TECH §4
- SPEC-003 TESTING U4–U8
- SPEC-002 TECH §6

## Files (chỉ được tạo/sửa các file này)

- `Sources/VaultPersistence/Repositories/GRDBOAuthClientRepository.swift`
- `Sources/VaultPersistence/Repositories/GRDBAccountRepository.swift`
- `Sources/VaultPersistence/Repositories/GRDBCredentialRepository.swift`
- `Sources/VaultPersistence/Repositories/GRDBSecretMetadataRepository.swift`
- `Tests/VaultPersistenceTests/CoreRepositoryTests.swift`

## Deliverables

1. 4 struct `GRDBXxxRepository: XxxRepository` với `init(db: VaultDatabase)`; hành vi đúng TECH §4 và doc comment protocol.
2. Lỗi miền: `DomainError.notFound`, `.hasDependents`; lỗi GRDB khác → `PersistenceError.database(message)`.

## Tests

SPEC-003 U4, U5, U6, U7, U8 + edge cases (list rỗng, updateStatus id lạ).

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter VaultPersistenceTests
```

## Lưu ý

- Dùng Record của T04, không định nghĩa Record mới.
- U7 cần ghi health result + audit: insert qua Record trực tiếp (repo đó là T06).

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T05.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
