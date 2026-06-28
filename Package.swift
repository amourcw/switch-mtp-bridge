// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwitchMTPBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SwitchMTPBridge", targets: ["SwitchMTPBridge"])
    ],
    targets: [
        .executableTarget(
            name: "SwitchMTPBridge",
            path: "Sources"
        )
    ]
)
