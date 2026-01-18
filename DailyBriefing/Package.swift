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
    ],
    targets: [
        .executableTarget(
            name: "DailyBriefing",
            dependencies: [
                "KeychainAccess",
            ],
            path: "Sources"
        )
    ]
)
