#!/bin/bash
# SPEC-001 U2: import cấm bị check-imports.sh bắt.
set -euo pipefail
cd "$(dirname "$0")/.."

bad="Sources/SecretVault/U2BadImport.swift"
out=$(mktemp)
cleanup() { rm -f "$bad" "$out"; }
trap cleanup EXIT

echo 'import TokenVault' > "$bad"

if ./scripts/check-imports.sh > "$out" 2>&1; then
    echo "U2 FAIL: check-imports phải exit 1 khi có import cấm"
    exit 1
fi
if ! grep -q "$bad" "$out"; then
    echo "U2 FAIL: output không nêu file vi phạm:"
    cat "$out"
    exit 1
fi

rm -f "$bad"
if ! ./scripts/check-imports.sh > "$out" 2>&1; then
    echo "U2 FAIL: check-imports phải exit 0 khi không còn vi phạm:"
    cat "$out"
    exit 1
fi

echo "U2: pass — import cấm bị bắt (exit 1 + đường dẫn), bỏ file thì exit 0"
