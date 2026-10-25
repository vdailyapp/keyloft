# SPEC-001: Khung SPM, CI và hạ tầng test — Tech Spec

**Status:** Draft
**Product spec:** ./PRODUCT.md
**Last updated:** 2026-10-25

## Problem

Repo trống. Cần chốt đồ thị target một lần, vì mọi task sau giả định target đã tồn tại.

## Relevant Code

- Chưa có code. Nguồn yêu cầu: `docs/PROJECT-SPEC.md` mục "Cấu trúc thư mục".

## Current State

Repo rỗng (2026-10-25).

## Proposed Changes

### 1. Cây thư mục

```
keyloft/
├── Package.swift
├── Makefile
├── .swift-format
├── .gitignore
├── .github/workflows/ci.yml
├── scripts/check-imports.sh
├── Sources/
│   ├── VaultDomain/VaultDomain.swift          # placeholder: public enum VaultDomain { static let version }
│   ├── VaultPersistence/VaultPersistence.swift
│   ├── SecretVault/SecretVault.swift
│   ├── TokenVault/TokenVault.swift
│   ├── Providers/Providers.swift
│   ├── HealthCheck/HealthCheck.swift
│   ├── VaultRuntime/VaultRuntime.swift
│   └── KeyloftCLI/Keyloft.swift                # @main AsyncParsableCommand, `--version` in "0.1.0"
└── Tests/
    ├── KeyloftTestSupport/KeyloftTestSupport.swift
    ├── VaultDomainTests/SmokeTests.swift
    ├── VaultPersistenceTests/SmokeTests.swift
    ├── SecretVaultTests/SmokeTests.swift
    ├── TokenVaultTests/SmokeTests.swift
    ├── ProvidersTests/SmokeTests.swift
    ├── HealthCheckTests/SmokeTests.swift
    ├── VaultRuntimeTests/SmokeTests.swift
    └── KeyloftCLITests/SmokeTests.swift        # @testable import KeyloftCLI
```

> **Deviation từ spec tổng:** thêm target `VaultRuntime` (composition root dùng chung cho App và
> CLI, xem SPEC-010) và `KeyloftTestSupport` (fake dùng chung). Cả hai không vi phạm quy tắc
> phụ thuộc: `VaultRuntime` là "package core" mà quy tắc 4 nhắc tới.

### 2. Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let strict: [SwiftSetting] = [.enableUpcomingFeature("ExistentialAny")]

let package = Package(
    name: "Keyloft",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "keyloft", targets: ["KeyloftCLI"]),
        .library(name: "VaultRuntime", targets: ["VaultRuntime"]),
        .library(name: "KeyloftTestSupport", targets: ["KeyloftTestSupport"]),   // cho KeyloftAppTests (SPEC-011)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "VaultDomain", swiftSettings: strict),
        .target(name: "VaultPersistence",
                dependencies: ["VaultDomain", .product(name: "GRDB", package: "GRDB.swift")],
                swiftSettings: strict),
        .target(name: "SecretVault", dependencies: ["VaultDomain"], swiftSettings: strict),
        .target(name: "TokenVault", dependencies: ["VaultDomain", "SecretVault"], swiftSettings: strict),
        .target(name: "Providers", dependencies: ["VaultDomain"], swiftSettings: strict),
        .target(name: "HealthCheck", dependencies: ["VaultDomain", "TokenVault", "Providers"],
                swiftSettings: strict),
        .target(name: "VaultRuntime",
                dependencies: ["VaultDomain", "VaultPersistence", "SecretVault", "TokenVault",
                               "Providers", "HealthCheck"],
                swiftSettings: strict),
        .executableTarget(name: "KeyloftCLI",
                dependencies: ["VaultRuntime", .product(name: "ArgumentParser", package: "swift-argument-parser")],
                swiftSettings: strict),

        .target(name: "KeyloftTestSupport",
                dependencies: ["VaultDomain", "SecretVault", "TokenVault", "Providers"],
                path: "Tests/KeyloftTestSupport", swiftSettings: strict),
        .testTarget(name: "VaultDomainTests", dependencies: ["VaultDomain", "KeyloftTestSupport"]),
        .testTarget(name: "VaultPersistenceTests", dependencies: ["VaultPersistence", "KeyloftTestSupport"]),
        .testTarget(name: "SecretVaultTests", dependencies: ["SecretVault", "KeyloftTestSupport"]),
        .testTarget(name: "TokenVaultTests", dependencies: ["TokenVault", "KeyloftTestSupport"]),
        .testTarget(name: "ProvidersTests", dependencies: ["Providers", "KeyloftTestSupport"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "HealthCheckTests", dependencies: ["HealthCheck", "Providers", "KeyloftTestSupport"]),
        .testTarget(name: "VaultRuntimeTests", dependencies: ["VaultRuntime", "KeyloftTestSupport"]),
        .testTarget(name: "KeyloftCLITests", dependencies: ["KeyloftCLI", "KeyloftTestSupport"]),
    ]
)
```

Swift 6 tools-version mặc định language mode 6 (strict concurrency complete). Tạo sẵn
`Tests/ProvidersTests/Fixtures/.gitkeep` để resource path tồn tại.

### 3. Makefile

```make
.PHONY: build test test-keychain lint format check-imports
build:          ; swift build
test:           ; swift test
test-keychain:  ; KEYLOFT_KEYCHAIN_TESTS=1 swift test --filter SecretVaultTests
lint:           ; swift format lint --strict -r Sources Tests && ./scripts/check-imports.sh
format:         ; swift format format -i -r Sources Tests
```

(`swift format` có sẵn trong toolchain Swift 6.)

### 4. scripts/check-imports.sh

Chặn các import SPM không bắt được (vì cùng package vẫn cho phép nếu ai đó lỡ thêm dependency):

- `Sources/VaultDomain/**`: chỉ được `import Foundation`.
- `Sources/SecretVault/**`: cấm `import TokenVault`.
- `Sources/Providers/**`: cấm `import TokenVault|SecretVault|VaultPersistence`.
- Mọi `Sources/**` trừ `VaultRuntime`, `KeyloftCLI`: cấm `import VaultPersistence` (chỉ composition
  root biết GRDB).

Script in file:dòng vi phạm, exit 1.

### 5. CI `.github/workflows/ci.yml`

`runs-on: macos-14`, chọn Xcode 16.x (`sudo xcode-select -s /Applications/Xcode_16.4.app`),
cache `.build`, chạy `swift build -Xswiftc -warnings-as-errors`, `make lint`, `make test`.

### 6. KeyloftTestSupport

T01 chỉ tạo file placeholder `public enum KeyloftTestSupport {}`. Fake được thêm ở T03/T07
(xem SPEC-002, SPEC-004).

## Implementation Steps

1. T01 — toàn bộ mục 1–6. Xong khi 3 lệnh make xanh local.

## Testing

See ./TESTING.md

## Risks and Rollback

- GRDB 7 yêu cầu Xcode 16+: CI phải chọn đúng Xcode.

## Open Questions

- Có dùng `swift-format` config mặc định không? Leaning: dùng mặc định, chỉ đổi
  `lineLength: 120`, `indentation: 4 spaces`.
