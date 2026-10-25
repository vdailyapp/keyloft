# Prompt review — GLM-5.3 review task của GLM-5.3-Flash

```text
Review task {{TASK}} của Keyloft. Bạn KHÔNG sửa code; chỉ báo lỗi.

Đọc: AGENTS.md, handoff/tasks/{{TASK}}-*.md, các mục spec task trỏ tới, handoff/reports/{{TASK}}.md,
và diff: `git diff main...HEAD`.

Kiểm tra theo thứ tự, mỗi mục trả lời PASS hoặc liệt kê lỗi kèm file:dòng:
1. Phạm vi: chỉ đụng file trong mục "Files"? Không sửa Package.swift?
2. Interface: chữ ký public khớp TECH.md từng ký tự (tên, nhãn tham số, async/throws, Sendable)?
3. Test: có đủ mọi ID ở mục "Tests"? Mỗi test assert đúng "Expected" trong TESTING.md (không chỉ
   #expect(true) hay assert yếu hơn)?
4. Đường lỗi: mọi case lỗi trong TECH.md đều được map, không có try? / catch rỗng / fatalError?
5. Bảo mật: không log/description lộ token/secret; không Date()/UUID()/URLSession trực tiếp trong
   logic; không gọi mạng thật trong test.
6. Concurrency: không @unchecked Sendable / DispatchQueue ngoài chỗ được phép.
7. Chạy: `make build && make lint && <lệnh Verify của task>` — dán kết quả tóm tắt.

Kết luận một dòng: APPROVE hoặc CHANGES REQUESTED + danh sách lỗi đánh số (ngắn, sửa được ngay).
Ghi kết quả vào cuối handoff/reports/{{TASK}}.md mục "Review".
```
