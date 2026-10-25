# T03: VaultDomain: protocol repo/infra + KeyloftTestSupport

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3-Flash** | [SPEC-002](../../specs/SPEC-002-vault-domain/) | 2 | T02 |

Branch: `task/T03-domain-protocols-testsupport` · Prompt: `handoff/templates/PROMPT-FLASH.md`

## Đọc trước

- `AGENTS.md`
- SPEC-002 TECH §6, §6b, §7, §8, §9
- SPEC-002 TESTING U12

## Files (chỉ được tạo/sửa các file này)

- `Sources/VaultDomain/Repositories.swift`
- `Sources/VaultDomain/Infrastructure.swift`
- `Sources/VaultDomain/DomainError.swift`
- `Tests/KeyloftTestSupport/FixedDateProvider.swift`
- `Tests/KeyloftTestSupport/SequentialIDGenerator.swift`
- `Tests/KeyloftTestSupport/SeededRandomSource.swift`
- `Tests/KeyloftTestSupport/StubHTTPClient.swift`
- `Tests/KeyloftTestSupport/InMemoryRepositories.swift`
- `Tests/KeyloftTestSupport/Fixtures.swift`
- `Tests/VaultDomainTests/TestSupportTests.swift`

## Deliverables

1. 6 protocol repository + `ProviderRegistry` + `AuditQuery` + `HealthCheckRetention` (TECH §6, §6b).
2. `DateProvider/IDGenerator/RandomSource/HTTPClient` + impl hệ thống; `URLSessionHTTPClient` mặc định dùng `URLSessionConfiguration.ephemeral`.
3. `DomainError`.
4. TestSupport: `FixedDateProvider` (`advance(by:)`), `SequentialIDGenerator`, `SeededRandomSource`, `StubHTTPClient` (TECH §9), actor `InMemory*Repository` cho 6 protocol (hành vi khớp mô tả GRDB ở SPEC-003 §4: retention 50, hasDependents, cascade), `InMemoryProviderRegistry`, `TestData` (provider Google/MS/Dropbox giả với URL `https://example.test/...`, client, account, credential).

## Tests

SPEC-002 U12 (+ test ngắn cho cascade/hasDependents của InMemory repo).

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter VaultDomainTests
```

## Lưu ý

- Class fake trong `Tests/` được dùng `NSLock` + `@unchecked Sendable` (ngoại lệ, comment 1 dòng). Không dùng `Mutex` (cần macOS 15).
- `StubHTTPClient.on(_:_:status:json:headers:)` cho phép đặt header (cần cho `WWW-Authenticate`) và có biến thể `delay:` (Duration) dùng ở SPEC-006 U4.
- `TestData` phải dựng `Provider` với quirks đầy đủ để test sau không phải tự dựng.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T03.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
