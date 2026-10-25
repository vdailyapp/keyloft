# T21: HealthCheck: HealthScheduler (trigger, 6h, backoff, dedupe)

| Model | Spec | Wave | Deps |
| --- | --- | --- | --- |
| **GLM-5.3** | [SPEC-008](../../specs/SPEC-008-health-check/) | 7 | T20 |

Branch: `task/T21-health-scheduler` · Prompt: `handoff/templates/PROMPT-PRO.md`

## Đọc trước

- `AGENTS.md`
- SPEC-008 PRODUCT §Behavior 1, 3, 4, 6
- SPEC-008 TECH §4
- SPEC-008 TESTING U19–U26

## Files (chỉ được tạo/sửa các file này)

- `Sources/HealthCheck/HealthScheduler.swift`
- `Sources/HealthCheck/Sleeper.swift`
- `Tests/HealthCheckTests/ManualSleeper.swift`
- `Tests/HealthCheckTests/HealthSchedulerTests.swift`

## Deliverables

1. `Sleeper`, `TaskSleeper`, `HealthTrigger`, `actor HealthScheduler` đúng TECH §4 (`updates` là AsyncStream multicast đơn giản: một continuation/subscriber).

## Tests

SPEC-008 U19–U26.

Mỗi test tên bắt đầu bằng ID (`@Test("U3: ...")`). Expected lấy nguyên từ TESTING.md.

## Verify

```bash
make build
make lint
swift test --filter HealthCheckTests
```

## Lưu ý

- `ManualSleeper`: mỗi `sleep` đăng ký (deadline, continuation); `advance(by:)` resume các deadline đã tới theo thứ tự.
- `stop()` hủy mọi task con; test kiểm không còn retry sau stop.

## Done khi

- [ ] Mọi lệnh Verify xanh
- [ ] Đủ test ID ở mục Tests
- [ ] Không đụng file ngoài mục Files
- [ ] `handoff/reports/T21.md` đã viết, nhánh đã push, BOARD (trên main) status = `review`
