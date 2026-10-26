#!/bin/bash
# lint-rules.sh — chặn tái phạm quy tắc AGENTS.md mà swift-format không bắt được:
#   1. `print(` trong Sources/ hoặc App/ (trừ Sources/KeyloftCLI — CLI in qua StandardStreams).
#   2. `try?` nuốt lỗi: bắt buộc có chú thích `// try?: <lý do cụ thể>` trên cùng dòng
#      hoặc dòng ngay trên. Không tính file test.
#   3. `Date()`/`UUID()` trong logic: chỉ Sources/VaultDomain/Infrastructure.swift (nơi định
#      nghĩa SystemDateProvider/SystemIDGenerator) và Sources/SecretVault/VaultLock.swift
#      (UUID cho key continuation nội bộ của khóa vault, không phải ID domain) được dùng;
#      chỗ khác phải có chú thích `// lint-allow: <lý do>`.
# In `file:line` cho từng vi phạm; thoát != 0 khi có vi phạm.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

violations=0

report() { # report <file> <line> <rule> <chi tiết>
  echo "$1:$2: [$3] $4"
  violations=$((violations + 1))
}

trim_and_check_comment() { # <file> <line> <marker> — trả 0 nếu dòng là chú thích thuần
  local file="$1" line="$2" marker="$3"
  local content prev
  content="$(sed -n "${line}p" "$file")"
  prev="$(sed -n "$((line - 1))p" "$file")"
  if [[ "$content" =~ ^[[:space:]]*// ]]; then
    return 0
  fi
  if [[ "$content" == *"$marker"* || "$prev" == *"$marker"* ]]; then
    return 0
  fi
  return 1
}

# --- 1. print( ---
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  line="${hit#*:}"
  line="${line%%:*}"
  report "$file" "$line" "print" "print( trong code production — dùng log/kênh lỗi thay thế"
done < <(grep -rn 'print(' Sources App --include='*.swift' | grep -v '^App/Tests/' | grep -v '^Sources/KeyloftCLI/' || true)

# --- 2. try? không có lý do ---
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  line="${hit#*:}"
  line="${line%%:*}"
  if trim_and_check_comment "$file" "$line" "// try?:"; then
    continue
  fi
  report "$file" "$line" "try?" "try? nuốt lỗi — thêm '// try?: <lý do cụ thể>' hoặc xử lý lỗi"
done < <(grep -rn 'try?' Sources App --include='*.swift' | grep -v '^App/Tests/' || true)

# --- 3. Date()/UUID() trong logic ---
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  line="${hit#*:}"
  line="${line%%:*}"
  # Ngoại lệ theo file (xem lý do ở đầu file này).
  if [[ "$file" == "Sources/VaultDomain/Infrastructure.swift" \
    || "$file" == "Sources/SecretVault/VaultLock.swift" ]]; then
    continue
  fi
  if trim_and_check_comment "$file" "$line" "// lint-allow:"; then
    continue
  fi
  report "$file" "$line" "clock" \
    "Date()/UUID() trực tiếp — đi qua DateProvider/IDGenerator hoặc '// lint-allow: <lý do>'"
done < <(grep -rnE 'Date\(\)|UUID\(\)' Sources App --include='*.swift' | grep -v '^App/Tests/' || true)

if [[ "$violations" -gt 0 ]]; then
  echo "lint-rules: $violations vi phạm"
  exit 1
fi
echo "lint-rules: ok"
