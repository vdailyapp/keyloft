#!/bin/bash
# Chặn các import mà SPM không bắt được (SPM chỉ chặn import target không khai báo
# dependency; các quy tắc kiến trúc trong AGENTS.md hẹp hơn đồ thị SPM).
# In <file>:<dòng> vi phạm, exit 1 nếu có vi phạm.
set -uo pipefail
cd "$(dirname "$0")/.."

violations=""

add() {
    violations+="$1"$'\n'
}

# Rule 1: Sources/VaultDomain chỉ được import Foundation.
# Ngoại lệ duy nhất: Infrastructure.swift được thêm import Security (SPEC-002).
for f in $(find Sources/VaultDomain -name '*.swift' 2>/dev/null); do
    allowed="Foundation"
    case "$f" in
        */Infrastructure.swift) allowed="Foundation Security" ;;
    esac
    while IFS=: read -r ln stmt; do
        [ -z "$ln" ] && continue
        mod=$(echo "$stmt" | awk '{print $2}')
        if ! echo " $allowed " | grep -q " $mod "; then
            add "$f:$ln: VaultDomain chỉ được import Foundation (Security chỉ ở Infrastructure.swift), thấy: import $mod"
        fi
    done < <(grep -nE '^[[:space:]]*import[[:space:]]+[A-Za-z_]' "$f" || true)
done

# Rule 2: SecretVault không import TokenVault (không có chiều ngược lại).
while IFS=: read -r f ln stmt; do
    [ -z "$f" ] && continue
    add "$f:$ln: SecretVault cấm import TokenVault, thấy: $stmt"
done < <(grep -RnE '^[[:space:]]*import[[:space:]]+TokenVault' Sources/SecretVault 2>/dev/null || true)

# Rule 3: Providers chỉ phụ thuộc VaultDomain.
while IFS=: read -r f ln stmt; do
    [ -z "$f" ] && continue
    add "$f:$ln: Providers cấm import TokenVault|SecretVault|VaultPersistence, thấy: $stmt"
done < <(grep -RnE '^[[:space:]]*import[[:space:]]+(TokenVault|SecretVault|VaultPersistence)' Sources/Providers 2>/dev/null || true)

# Rule 4: import VaultPersistence chỉ dành cho VaultRuntime và KeyloftCLI
# (composition root mới được biết GRDB tồn tại).
for dir in Sources/*/; do
    name=$(basename "$dir")
    [ "$name" = "VaultRuntime" ] && continue
    [ "$name" = "KeyloftCLI" ] && continue
    while IFS=: read -r f ln stmt; do
        [ -z "$f" ] && continue
        add "$f:$ln: chỉ VaultRuntime/KeyloftCLI được import VaultPersistence, thấy: $stmt"
    done < <(grep -RnE '^[[:space:]]*import[[:space:]]+VaultPersistence' "$dir" 2>/dev/null || true)
done

if [ -n "$violations" ]; then
    echo "check-imports: phát hiện import vi phạm quy tắc kiến trúc:"
    echo "$violations"
    exit 1
fi
echo "check-imports: ok"
