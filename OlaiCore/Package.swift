// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OlaiCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "OlaiCore", targets: ["OlaiCore"])
    ],
    targets: [
        .target(name: "OlaiCore"),
        .testTarget(name: "OlaiCoreTests", dependencies: ["OlaiCore"])
    ]
)
