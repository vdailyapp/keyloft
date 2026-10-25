# Handoff — giao task cho zcode (GLM-5.3 / GLM-5.3-Flash)

Thư mục này biến các spec trong `specs/` thành **29 task tự chứa**, mỗi task = 1 nhánh = 1 PR,
giao cho agent zcode chạy model GLM-5.3 hoặc GLM-5.3-Flash.

```
handoff/
├── README.md              # file này: quy trình, phân model, cách chạy song song
├── BOARD.md               # bảng trạng thái mọi task (nguồn sự thật về tiến độ)
├── tasks/Txx-*.md         # đề bài từng task (đọc kèm AGENTS.md + spec)
├── reports/Txx.md         # agent viết sau khi xong
└── templates/
    ├── PROMPT-FLASH.md    # prompt mở phiên cho GLM-5.3-Flash
    ├── PROMPT-PRO.md      # prompt mở phiên cho GLM-5.3
    ├── PROMPT-REVIEW.md   # prompt review (GLM-5.3 review task của Flash)
    └── REPORT.md          # khung report
```

## Phân model

| Model | Nhận loại task | Lý do |
| --- | --- | --- |
| **GLM-5.3** | Concurrency (actor, single-flight, task race), API nền tảng khó (NWListener, Keychain/SecItem, LAContext, ASWebAuthenticationSession, ký app), điều phối nhiều service, state machine health, review | Sai ở đây là lỗi bảo mật hoặc lỗi chỉ lộ ra khi chạy thật; cần suy luận nhiều bước và tự quyết chi tiết TECH.md chưa nói |
| **GLM-5.3-Flash** | Type/entity, repository CRUD, mã hóa form/URL, parse JSON fixture, provider tĩnh, CLI, view SwiftUI có model rõ | Interface đã chốt đủ trong TECH.md; test có bảng kỳ vọng cụ thể; làm theo khuôn |

Quy tắc: task Flash **không được** tự đổi public API ngoài những gì task ghi. Gặp chỗ spec thiếu
→ dừng, ghi câu hỏi vào report mục "Blocked", đặt status `blocked`.

Tổng: 11 task GLM-5.3, 18 task Flash (xem `BOARD.md`).

## Chế độ tự chạy

Muốn zcode tự nhận và làm hết BOARD (một phiên GLM-5.3 làm Lead/review/merge, một phiên Flash
làm Builder): dùng prompt trong [`AUTOPILOT.md`](AUTOPILOT.md). Phần dưới là quy trình thủ công
từng task.

## Quy trình mỗi task

1. **Chọn task**: trong `BOARD.md`, status `todo` và mọi task ở cột `Deps` đã `done`.
2. **Tạo nhánh**: `git switch -c task/Txx-<slug>` từ `main` mới nhất.
3. **Mở zcode** ở root repo, chọn model theo cột `Model`, dán prompt từ
   `templates/PROMPT-FLASH.md` hoặc `PROMPT-PRO.md` (thay `{{TASK}}` = `T05`).
4. Agent làm, chạy lệnh verify trong task, viết `reports/Txx.md`, push nhánh, rồi đặt status
   `review` trong `BOARD.md` trên `main`.
5. **Review**:
   - Task Flash → mở phiên GLM-5.3 mới với `templates/PROMPT-REVIEW.md`. Có lỗi → quay lại phiên
     Flash cũ (giữ ngữ cảnh) với danh sách lỗi.
   - Task GLM-5.3 → người review (hoặc Claude `/code-review`).
6. **Merge** vào `main` (squash, tiêu đề `SPEC-NNN/Txx: <title>`), đặt status `done`.

Agent **không** được: sửa `Package.swift` (trừ T01), sửa file ngoài mục "Files" của task, xóa/skip
test, commit lên `main`.

## Chạy song song

Các task cùng **Wave** không chung file → chạy song song được (mỗi task một nhánh/worktree):

```bash
git worktree add ../keyloft-T05 -b task/T05-core-repos
git worktree add ../keyloft-T06 -b task/T06-health-audit-repos
```

| Wave | Task | Ghi chú |
| --- | --- | --- |
| 0 | T01 | Khung — phải xong trước mọi thứ |
| 1 | T02 | Entity — mọi task sau phụ thuộc |
| 2 | T03, T12 | T03 là nền cho test; T12 chỉ cần T02 |
| 3 | T04, T07, T10, T13, T17 | |
| 4 | T05, T06, T08, T11, T14, T18, T19 | |
| 5 | T09, T15, T16 | |
| 6 | T20, T22 | |
| 7 | T21 | |
| 8 | T23 | Composition root |
| 9 | T24, T25 | CLI và app shell |
| 10 | T26, T27, T28 | Feature UI |
| 11 | T29 | Review bảo mật + E2E thủ công |

Đường găng: T01 → T02 → T03 → T10 → T11 → T16 → T20 → T21 → T23 → T25 → T26 → T29.

## Kích thước & tiêu chí task

- Mỗi task ≤ ~500 dòng code + test, ≤ 10 file, chạm đúng 1 target (trừ T23/T25).
- Task có danh sách test ID lấy từ `TESTING.md` — agent phải viết **đủ** các ID đó.
- "Xong" = `make build && make lint && swift test --filter <...>` xanh + report.

## Khi spec sai

Agent phát hiện TECH.md lệch thực tế (API Apple khác, provider đổi endpoint) → GLM-5.3 được phép
sửa TECH.md trong cùng PR và ghi "Deviations" trong report; Flash chỉ ghi "Blocked".
