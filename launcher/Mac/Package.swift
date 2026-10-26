// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwitchMac",
    platforms: [.macOS(.v26)],
    products: [.library(name: "SwitchMacRuntime", targets: ["SwitchMacRuntime"])],
    dependencies: [.package(name: "iSwitchCore", path: "..")],
    targets: [
        .target(name: "SwitchMacRuntime", dependencies: [.product(name: "iSwitchCore", package: "iSwitchCore")]),
        .testTarget(name: "SwitchMacRuntimeTests", dependencies: ["SwitchMacRuntime"])
    ]
)
