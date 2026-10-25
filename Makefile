.PHONY: build test test-keychain lint format check-imports
build:          ; swift build
test:           ; swift test
test-keychain:  ; KEYLOFT_KEYCHAIN_TESTS=1 swift test --filter SecretVaultTests
lint:           ; swift format lint --strict -r Sources Tests && ./scripts/check-imports.sh
format:         ; swift format format -i -r Sources Tests
check-imports:  ; ./scripts/check-imports.sh
