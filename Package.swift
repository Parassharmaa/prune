// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Prune",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Prune", targets: ["Prune"])
    ],
    targets: [
        .executableTarget(
            name: "Prune",
            path: "Sources/Prune"
        )
    ]
)
