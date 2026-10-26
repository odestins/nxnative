// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "SwitchSaveSync", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SwitchSaveSync", targets: ["SwitchSaveSync"])],
    targets: [.target(name: "SwitchSaveSync"), .testTarget(name: "SwitchSaveSyncTests", dependencies: ["SwitchSaveSync"])])
