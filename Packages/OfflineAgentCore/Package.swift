// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OfflineAgentCore",
    platforms: [
        .iOS(.v15),
        // `swift test` runs on the host (macOS). Explicitly declare a modern macOS
        // deployment target so Swift Concurrency APIs are available.
        .macOS(.v13),
    ],
    products: [
        .library(name: "OfflineAgentCore", targets: ["OfflineAgentCore"]),
    ],
    targets: [
        .target(
            name: "OfflineAgentCore",
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "OfflineAgentCoreTests",
            dependencies: ["OfflineAgentCore"],
            path: "Tests"
        ),
    ]
)

