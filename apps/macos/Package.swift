// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        // Agent-neutral model, session sources and presentation policy. No UI.
        .target(name: "CompanionCore"),
        // The macOS app: edge panel window + SwiftUI views.
        .executableTarget(name: "AgentCompanion", dependencies: ["CompanionCore"],
                          resources: [.copy("Resources/ProviderIcons")]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"]),
    ]
)
