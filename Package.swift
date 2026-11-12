// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwitchDeck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwitchKit", targets: ["SwitchKit"]),
        .executable(name: "SwitchDeck", targets: ["SwitchDeckApp"]),
    ],
    targets: [
        .target(name: "SwitchKit"),
        .executableTarget(name: "SwitchDeckApp", dependencies: ["SwitchKit"]),
        .testTarget(name: "SwitchKitTests", dependencies: ["SwitchKit"]),
    ]
)
