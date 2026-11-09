// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MinerGuru",
    defaultLocalization: "de",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MinerGuru", targets: ["MinerGuru"])
    ],
    targets: [
        .executableTarget(
            name: "MinerGuru",
            path: "MinerGuru",
            exclude: [
                "Info.plist",
                "MinerGuru.entitlements",
                "Assets.xcassets",
                "AppIcon.icns"
            ]
        ),
        .testTarget(
            name: "MinerGuruTests",
            dependencies: ["MinerGuru"],
            path: "MinerGuruTests"
        )
    ]
)
