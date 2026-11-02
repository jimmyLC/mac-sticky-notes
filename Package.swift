// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IdeaMemo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IdeaMemo", targets: ["IdeaMemo"]),
    ],
    targets: [
        .target(name: "StickyCore", path: "Sources/StickyCore"),
        .executableTarget(
            name: "IdeaMemo",
            dependencies: ["StickyCore"],
            path: "Sources/IdeaMemo",
            exclude: ["Localization"]
        ),
        .testTarget(
            name: "StickyCoreTests",
            dependencies: ["StickyCore"],
            path: "Tests/StickyCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
