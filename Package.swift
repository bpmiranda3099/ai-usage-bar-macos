// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ai-agents-usage-bar",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "UsageBarCore",
            path: "Sources/UsageBarCore",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "AIAgentsUsageBar",
            dependencies: ["UsageBarCore"],
            path: "Sources/AIAgentsUsageBar"
        ),
        .testTarget(
            name: "UsageBarCoreTests",
            dependencies: ["UsageBarCore"],
            path: "Tests/UsageBarCoreTests"
        ),
    ]
)
