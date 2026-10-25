# Prompt mở phiên — GLM-5.3-Flash

Dán nguyên khối dưới vào zcode (thay `{{TASK}}`):

```text
Bạn đang làm task {{TASK}} của dự án Keyloft (Swift 6, macOS 14, SPM).

Đọc theo đúng thứ tự, KHÔNG bỏ bước:
1. AGENTS.md
2. handoff/tasks/{{TASK}}-*.md
3. Các mục spec mà task liệt kê ở "Đọc trước" (chỉ các mục đó)
4. Code hiện có trong các file ở mục "Files" của task

Luật cứng:
- Chỉ tạo/sửa file trong mục "Files". Không sửa Package.swift.
- Viết đúng chữ ký (signature) trong TECH.md. Không thêm public API khác ngoài mục "Deliverables".
- Viết ĐỦ các test ID ở mục "Tests"; tên test bắt đầu bằng ID, ví dụ @Test("U3: ...").
- Không xóa/skip test. Không dùng try? để nuốt lỗi. Không log token/secret.
- Nếu spec thiếu thông tin để làm tiếp: dừng, ghi câu hỏi vào handoff/reports/{{TASK}}.md mục
  "Blocked", đặt status task trong handoff/BOARD.md (trên main) = blocked. Không tự đoán interface.

Làm xong:
1. Chạy mọi lệnh ở mục "Verify" của task; tất cả phải xanh.
2. Đọc lại diff của bạn một lần.
3. Viết handoff/reports/{{TASK}}.md theo handoff/templates/REPORT.md.
4. Commit trên nhánh task: "SPEC-NNN/{{TASK}}: <tiêu đề task>" và push nhánh.
5. Trên main: sửa Status của {{TASK}} trong handoff/BOARD.md thành review, commit
   "board: {{TASK}} review", push. (Không sửa BOARD.md trên nhánh task.)

Bắt đầu bằng việc tóm tắt trong 5 dòng: file sẽ tạo, test sẽ viết, lệnh verify.
```
