// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PhotoOverlay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Overlay", targets: ["PhotoOverlay"])
    ],
    targets: [
        .executableTarget(
            name: "PhotoOverlay",
            path: "Sources/PhotoOverlay"
        ),
        .testTarget(
            name: "PhotoOverlayTests",
            path: "Tests/PhotoOverlayTests"
        )
    ]
)
