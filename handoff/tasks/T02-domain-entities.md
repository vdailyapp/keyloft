# T02: VaultDomain: ID, enum, ScopeSet, entity

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-002](../../specs/SPEC-002-vault-domain/) | 1 | T01 |

Branch: `task/T02-domain-entities` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-002 PRODUCT.md
- SPEC-002 TECH §1–§5
- SPEC-002 TESTING U1–U11

## Files (chỉ được tạo/sửa các file này)

- `Sources/VaultDomain/Identifiers.swift`
- `Sources/VaultDomain/Enums.swift`
- `Sources/VaultDomain/ScopeSet.swift`
- `Sources/VaultDomain/Provider.swift`
- `Sources/VaultDomain/OAuthClient.swift`
- `Sources/VaultDomain/Account.swift`
- `Sources/VaultDomain/Credential.swift`
- `Sources/VaultDomain/Secret.swift`
- `Sources/VaultDomain/AccessToken.swift`
- `Sources/VaultDomain/HealthCheckResult.swift`
- `Sources/VaultDomain/AuditEvent.swift`
- `Tests/VaultDomainTests/*.swift`

## Deliverables

1. Mọi type ở TECH §2–§5, đúng tên/field/kiểu, kèm `public init` memberwise.
2. ID Codable = chuỗi UUID đơn (singleValueContainer).
3. `ScopeSet` Codable = mảng đã sắp xếp; `spaceDelimited` sắp xếp.
4. `AccessToken` không Codable; `description`/`debugDescription` che value.
5. Xóa placeholder `VaultDomain.swift` nếu không còn cần (giữ `version` ở `Enums.swift`).

## Tests

SPEC-002 U1–U11.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter VaultDomainTests
```

## Lưu ý

- `ProviderQuirks` có đủ field ở TECH §5 (kể cả `authorizationResponseIssSupported`, `scopeAliases`, `unechoedScopes`, `refreshIncludesScope`).
- `RevocationStyle` có associated value → tự viết Codable (key `type` + payload) hoặc dùng synthesized Codable của Swift 5.5+ (được).
- Không import gì ngoài Foundation.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T02.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
