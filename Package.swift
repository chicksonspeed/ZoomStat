// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZoomStat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZoomStatCore", targets: ["ZoomStatCore"]),
        .executable(name: "zoomstat-cli", targets: ["zoomstat-cli"]),
        .executable(name: "ZoomStat", targets: ["ZoomStat"]),
    ],
    targets: [
        .target(name: "ZoomStatCore"),
        .executableTarget(name: "zoomstat-cli", dependencies: ["ZoomStatCore"]),
        .executableTarget(name: "ZoomStat", dependencies: ["ZoomStatCore"]),
        .testTarget(name: "ZoomStatCoreTests", dependencies: ["ZoomStatCore"]),
    ]
)
