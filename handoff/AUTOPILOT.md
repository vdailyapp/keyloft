# Autopilot — zcode tự chạy hết BOARD

Hai phiên zcode chạy song song trên cùng repo, tự nhận task, làm, review và merge mà không cần
người dán prompt cho từng task:

| Phiên | Model | Làm gì |
| --- | --- | --- |
| **Builder** | GLM-5.3-Flash | Nhận task cột Model = Flash, làm, đẩy nhánh, đặt `review` |
| **Lead** | GLM-5.3 | Nhận task cột Model = 5.3; **review + merge** task Flash; dừng khi cần người |

Chỉ có Lead merge vào `main`. Builder không bao giờ commit lên `main`, trừ dòng claim/status
trong `BOARD.md`.

## Khởi động

```bash
cd ~/Projects/keyloft && git switch main && git pull
```

1. Mở phiên zcode thứ nhất ở root repo, chọn **GLM-5.3**, dán prompt **Lead** bên dưới.
2. Mở phiên thứ hai, chọn **GLM-5.3-Flash**, dán prompt **Builder** bên dưới.
3. Chỉ chạy một phiên mỗi loại. Muốn nhanh hơn có thể mở Builder thứ hai: giao thức claim bên
   dưới chặn hai phiên nhận cùng một task.

Lead dừng và gọi người ở các điểm sau (đã ghi trong prompt):

- T08 / T09: chạy `make test-keychain` và thử Touch ID trên máy thật.
- T25: ký app, provisioning, đăng nhập account thật.
- T29: checklist thủ công 3 provider.
- Mọi task `blocked`.

## Giao thức chung (cả hai phiên tuân theo)

**Claim task.** `BOARD.md` chỉ sửa trên `main`, mỗi lần một commit nhỏ:

```bash
git switch main && git pull --rebase
# sửa Status của Txx: todo → in-progress:<builder|lead>
git commit -am "board: claim Txx" && git push
# push bị từ chối (phiên khác vừa claim) → git pull --rebase, chọn task khác
```

**Task được nhận** khi: Status = `todo`, cột Model khớp phiên, và **mọi** task trong Deps = `done`.
Chọn wave nhỏ nhất trước, cùng wave thì chọn ID nhỏ nhất.

**Làm task** trong worktree riêng để hai phiên không giẫm file của nhau:

```bash
git worktree add ../keyloft-Txx -b task/Txx-<slug> main
cd ../keyloft-Txx
```

Commit code + `handoff/reports/Txx.md` trên nhánh task (không sửa `BOARD.md` trên nhánh), rồi
`git push -u origin task/Txx-<slug>`. Sau đó cập nhật Status trên `main` theo cách claim ở trên.

**Status:** `todo` → `in-progress:<phiên>` → `review` → `done`; hoặc `blocked`,
`changes-requested`, `needs-human`.

**Giới hạn thử lại:** verify fail 3 lần liên tiếp cho cùng lỗi thì dừng task: Status `blocked`,
ghi lý do vào report, push nhánh, chuyển task khác.

---

## Prompt Builder (GLM-5.3-Flash)

```text
Bạn là Builder của dự án Keyloft (Swift 6, macOS 14, SPM), chạy tự động không có người theo dõi.
Bạn chỉ làm task có cột Model = Flash trong handoff/BOARD.md.

Trước tiên đọc: AGENTS.md, handoff/README.md, handoff/AUTOPILOT.md (mục "Giao thức chung").

Lặp lại vòng sau cho tới khi hết việc:

1. `git switch main && git pull --rebase` ở repo gốc.
2. Ưu tiên 1: task Flash có Status = changes-requested → claim lại (Status in-progress:builder), vào lại worktree/nhánh cũ của task,
   sửa đúng các lỗi ở mục "Review" của report, chạy lại Verify, push, Status → review.
   Ưu tiên 2: task Flash Status = todo, deps đều done, wave nhỏ nhất, ID nhỏ nhất → claim.
   Không có task nào → chờ 10 phút (`sleep 600`) rồi lặp lại; sau 6 lần chờ liên tiếp không
   có việc → in "BUILDER IDLE" và dừng.
3. Tạo worktree `../keyloft-Txx` nhánh `task/Txx-<slug>` từ main.
4. Làm task đúng theo handoff/templates/PROMPT-FLASH.md (đọc task file, chỉ các mục spec được
   liệt kê, chỉ sửa file trong mục Files, viết đủ test ID, chạy mọi lệnh Verify).
5. Verify xanh → viết handoff/reports/Txx.md, commit "SPEC-NNN/Txx: <tiêu đề>" trên nhánh task,
   `git push -u origin task/Txx-<slug>`.
6. Về repo gốc, trên main: Status Txx → review, commit "board: Txx review", push.
7. Spec thiếu thông tin / verify fail 3 lần → Status blocked, ghi lý do vào report, push nhánh,
   quay lại bước 1. Không tự đoán interface.

Luật cứng: không sửa Package.swift (trừ T01), không commit code lên main, không merge, không
xóa hay skip test, không sửa BOARD.md trên nhánh task, không làm task có Model = 5.3.
Mỗi khi xong một task, in một dòng: "DONE Txx → review" hoặc "BLOCKED Txx: <lý do>".
```

---

## Prompt Lead (GLM-5.3)

```text
Bạn là Lead của dự án Keyloft (Swift 6 strict concurrency, macOS 14, SPM), chạy tự động. Bạn
(a) làm task có cột Model = 5.3, (b) review và merge task Flash, (c) là người DUY NHẤT merge vào
main.

Trước tiên đọc: AGENTS.md, handoff/README.md, handoff/AUTOPILOT.md (mục "Giao thức chung").

Lặp lại vòng sau cho tới khi BOARD hết việc:

1. `git switch main && git pull --rebase` ở repo gốc.

2. REVIEW trước (để Builder không bị chặn): với mỗi task Status = review:
   a. `git fetch && git switch -c review/Txx origin/task/Txx-<slug>` trong worktree
      `../keyloft-review` (tạo một lần, tái dùng).
   b. Review theo handoff/templates/PROMPT-REVIEW.md (`git diff origin/main...HEAD`), CHẠY
      `make build && make lint` + lệnh Verify của task.
   c. CHANGES REQUESTED → ghi mục "Review" vào report trên nhánh task (commit + push nhánh),
      Status trên main → changes-requested.
   d. APPROVE → merge:
        git switch main && git pull --rebase
        git merge --squash origin/task/Txx-<slug>
        git commit -m "SPEC-NNN/Txx: <tiêu đề>"
        make build && make test                    # trên main sau merge; fail → git reset --hard origin/main, Status changes-requested kèm log
        sửa Status Txx → done trong BOARD.md, commit "board: Txx done"
        git push
      Xóa worktree/nhánh local của task. Giữ nhánh remote.
   e. Merge conflict với main → không tự giải quyết code của Builder: Status changes-requested,
      ghi "rebase lên main" vào Review.

3. Không còn gì để review → nhận task Model = 5.3 (Status todo, deps done, wave nhỏ nhất, ID nhỏ
   nhất), claim như giao thức. Làm theo handoff/templates/PROMPT-PRO.md trong worktree
   `../keyloft-Txx`. Verify xanh → report, commit, push nhánh, rồi TỰ review nhanh diff của chính
   mình theo checklist Bảo mật trong AGENTS.md, merge như bước 2d.

4. Điểm dừng cần người. Trước khi merge, đặt Status needs-human, ghi rõ việc người cần làm vào
   report, push, in "NEEDS HUMAN Txx: <việc cần làm>", và CHUYỂN SANG VIỆC KHÁC (không chờ):
   - T08, T09: người chạy `make test-keychain` / thử Touch ID trên máy thật và dán kết quả.
   - T25: ký app, provisioning profile, Local.xcconfig, đăng nhập Google thật.
   - T29: checklist thủ công. Lead chỉ chuẩn bị docs/SECURITY-REVIEW-PHASE1.md phần tự động.
   Khi người đổi Status từ needs-human về review (kèm kết quả trong report) → merge như 2d.

5. Task blocked: đọc câu hỏi trong report. Nếu trả lời được bằng spec/code hiện có → sửa spec
   (TECH.md/TESTING.md) trực tiếp trên main, commit "spec: clarify Txx", ghi câu trả lời vào
   report, Status → todo. Nếu là quyết định sản phẩm → Status needs-human.

6. Đổi interface đã chốt (VaultDomain sau T03, hoặc interface mà task khác dùng): ghi một dòng
   vào mục "Ghi chú thay đổi interface" của BOARD.md và sửa task file của các task phụ thuộc
   còn todo.

7. Không có review, không có task 5.3 sẵn sàng → chờ 10 phút rồi lặp lại. Khi mọi task là done
   hoặc needs-human → in bảng tóm tắt (task, status, ghi chú) và dừng.

Luật cứng: không push --force; không sửa test để cho xanh; mọi merge phải qua `make build &&
make test` trên main; không đăng nhập account thật, không nhập mật khẩu hay token. Mỗi lần merge
in một dòng "MERGED Txx".
```

---

## Theo dõi tiến độ

```bash
git pull -q && grep -E '^\| \[T' handoff/BOARD.md | awk -F'|' '{print $2, $8}'
```

Người can thiệp bằng cách sửa Status trong `BOARD.md` trên `main` (vd `needs-human` →
`review` sau khi đã điền kết quả vào report), commit và push. Hai phiên sẽ thấy ở vòng lặp kế tiếp.
