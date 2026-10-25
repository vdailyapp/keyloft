# T20: HealthCheck: 5 tầng + map trạng thái

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-008](../../specs/SPEC-008-health-check/) | 6 | T16, T19 |

Branch: `task/T20-health-checker` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-008 toàn bộ
- SPEC-006 TECH §2
- SPEC-007 TECH §4

## Files (chỉ được tạo/sửa các file này)

- `Sources/HealthCheck/HealthPolicy.swift`
- `Sources/HealthCheck/HealthOutcome.swift`
- `Sources/HealthCheck/HealthChecker.swift`
- `Tests/HealthCheckTests/HealthOutcomeTests.swift`
- `Tests/HealthCheckTests/HealthCheckerTests.swift`
- `Tests/HealthCheckTests/FakeProbe.swift`

## Deliverables

1. `HealthPolicy`, `LayerFailure`, `status(for:warnings:)`, `actor HealthChecker` đúng TECH §2–§3.

## Tests

SPEC-008 U1–U18 + property test 1000 lượt transient.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter HealthCheckTests
```

## Lưu ý

- Mọi đường lỗi tầng là dữ liệu trong `checks`, không throw.
- Chuỗi `error` lấy từ tên case lỗi, không `String(describing:)` của response.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T20.md` đã viết, BOARD status = `review`
