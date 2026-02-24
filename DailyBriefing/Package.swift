// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DailyBriefing",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DailyBriefing", targets: ["DailyBriefing"])
    ],
    dependencies: [
        // OAuth / Keychain
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        // In-app updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "DailyBriefing",
            dependencies: [
                "KeychainAccess",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            exclude: [
                "Core/Services/ModelSelection/README.md",
                "Core/Services/ModelSelection/INTEGRATION.md",
            ],
            resources: [
                .process("Resources")
                // Note: Metal shaders are embedded as source strings in the Swift files
                // .metal files in UI/Shaders/ are kept as reference only
            ]
        )
    ]
)
