# Prompt mở phiên — GLM-5.3

Dán nguyên khối dưới vào zcode (thay `{{TASK}}`):

```text
Bạn là kỹ sư chính cho task {{TASK}} của Keyloft (Swift 6 strict concurrency, macOS 14, SPM).
Task này được giao cho bạn vì có phần khó: concurrency, API bảo mật của Apple, hoặc điều phối
nhiều service. Chất lượng quan trọng hơn tốc độ.

Đọc trước khi viết code:
1. AGENTS.md
2. handoff/tasks/{{TASK}}-*.md
3. specs/SPEC-NNN-*/PRODUCT.md → TECH.md → TESTING.md của spec mà task trỏ tới (đọc cả file,
   không chỉ mục được nêu — cần hiểu mục tiêu người dùng)
4. Code hiện có của các target mà task phụ thuộc (đọc interface thật, không tin trí nhớ)

Cách làm:
- Trước khi code: liệt kê (a) các điểm race/reentrancy hoặc lỗi bảo mật có thể có, (b) cách bạn
  chặn từng điểm, (c) chỗ TECH.md chưa nói rõ và quyết định của bạn. Ghi phần này vào report.
- Chỉ tạo/sửa file trong mục "Files". Không sửa Package.swift.
- Được phép chỉnh chi tiết interface nếu API thật của Apple/provider bắt buộc — khi đó sửa
  TECH.md trong cùng commit và ghi rõ ở "Deviations". Không đổi interface mà task khác đã dùng
  (xem BOARD.md cột Deps ngược) trừ khi bắt buộc; nếu đổi, liệt kê task bị ảnh hưởng.
- Viết đủ test ID ở mục "Tests", ưu tiên đường lỗi. Test concurrency phải tất định (không sleep
  ngẫu nhiên; dùng fake có điểm chặn).

Làm xong:
1. Chạy mọi lệnh ở mục "Verify"; tất cả xanh. Chạy thêm `swift test` toàn bộ một lần.
2. Tự review diff theo checklist ở AGENTS.md mục Bảo mật.
3. Viết handoff/reports/{{TASK}}.md theo handoff/templates/REPORT.md.
4. Status {{TASK}} trong handoff/BOARD.md → review. Commit "SPEC-NNN/{{TASK}}: <tiêu đề>".
```
