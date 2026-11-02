// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStickyNotes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacStickyNotes", targets: ["MacStickyNotes"]),
    ],
    targets: [
        .target(name: "StickyCore", path: "Sources/StickyCore"),
        .executableTarget(
            name: "MacStickyNotes",
            dependencies: ["StickyCore"],
            path: "Sources/MacStickyNotes",
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
