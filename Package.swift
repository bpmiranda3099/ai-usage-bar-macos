// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ai-agents-usage-bar",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "AIAgentsUsageBar",
            path: "Sources/AIAgentsUsageBar",
            resources: [.copy("Resources")]
        )
    ]
)
