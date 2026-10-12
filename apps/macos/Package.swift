// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Vibecheck",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // Agent-neutral model, session sources and presentation policy. No UI.
        .target(name: "CompanionCore"),
        // The macOS app: edge panel window + SwiftUI views.
        .executableTarget(name: "Vibecheck", dependencies: ["CompanionCore", .product(name: "Sparkle", package: "Sparkle")],
                          exclude: ["Orbs/LICENSE"],
                          resources: [.copy("Resources/ProviderIcons"), .copy("Resources/BrandIcons"),
                                      .copy("Resources/FrameworkIcons")]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"], resources: [.copy("Fixtures")]),
    ]
)
