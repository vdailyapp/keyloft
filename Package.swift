// swift-tools-version: 6.0
import PackageDescription

let strict: [SwiftSetting] = [.enableUpcomingFeature("ExistentialAny")]

let package = Package(
    name: "Keyloft",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "keyloft", targets: ["KeyloftCLI"]),
        .library(name: "VaultRuntime", targets: ["VaultRuntime"]),
        .library(name: "KeyloftTestSupport", targets: ["KeyloftTestSupport"]),  // cho KeyloftAppTests (SPEC-011)
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
