// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iSwitchCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "iSwitchCore", targets: ["iSwitchCore"])],
    targets: [
        .target(name: "iSwitchCore", path: "Core"),
        .testTarget(name: "iSwitchCoreTests", dependencies: ["iSwitchCore"], path: "Tests")
    ]
)
