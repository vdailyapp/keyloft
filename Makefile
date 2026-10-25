.PHONY: build test test-keychain lint format check-imports app app-test
build:          ; swift build
test:           ; swift test
test-keychain:  ; KEYLOFT_KEYCHAIN_TESTS=1 swift test --filter SecretVaultTests
lint:           ; swift format lint --strict -r Sources Tests && ./scripts/check-imports.sh
format:         ; swift format format -i -r Sources Tests
check-imports:  ; ./scripts/check-imports.sh

# Sinh project Xcode + build app (đính Local.xcconfig nếu có để ký thật).
app:
	cd App && xcodegen generate
	@if [ -f App/Local.xcconfig ]; then \
		set -o pipefail && xcodebuild -project App/Keyloft.xcodeproj -scheme Keyloft -configuration Debug build -xcconfig App/Local.xcconfig; \
	else \
		set -o pipefail && xcodebuild -project App/Keyloft.xcodeproj -scheme Keyloft -configuration Debug build; \
	fi
	@$(MAKE) embed-cli

# Embed CLI keyloft vào app vừa build + ký lại (codesign đòi ký lại sau khi đổi bundle).
embed-cli:
	swift build -c release --product keyloft
	@APP=$$(find $(HOME)/Library/Developer/Xcode/DerivedData/Keyloft-*/Build/Products/Debug -maxdepth 1 -name 'Keyloft.app' | head -1); \
	if [ -n "$$APP" ]; then \
		cp .build/release/keyloft "$$APP/Contents/MacOS/keyloft"; \
		codesign --force --identifier app.vdaily.keyloft.cli -s - "$$APP/Contents/MacOS/keyloft"; \
		codesign --force -s - "$$APP"; \
		echo "CLI embedded: $$APP/Contents/MacOS/keyloft"; \
	else \
		echo "Không tìm thấy Keyloft.app trong DerivedData" >&2; exit 1; \
	fi

app-test:
	cd App && xcodegen generate
	@if [ -f App/Local.xcconfig ]; then \
		set -o pipefail && xcodebuild test -project App/Keyloft.xcodeproj -scheme Keyloft -xcconfig App/Local.xcconfig; \
	else \
		set -o pipefail && xcodebuild test -project App/Keyloft.xcodeproj -scheme Keyloft; \
	fi
