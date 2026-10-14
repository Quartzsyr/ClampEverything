// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClampEverything",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClampEverything", targets: ["ClampEverything"])],
    targets: [
        .target(name: "ClampCore"),
        .executableTarget(name: "ClampEverything", dependencies: ["ClampCore"], resources: [.copy("Resources/Generated")]),
        .testTarget(name: "ClampCoreTests", dependencies: ["ClampCore"]),
        .testTarget(name: "ClampAppTests", dependencies: ["ClampEverything", "ClampCore"])
    ]
)
