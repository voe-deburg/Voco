// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Voco",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Voco", targets: ["Voco"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Voco",
            dependencies: [],
            path: "Typeless"
        ),
        .testTarget(
            name: "TypelessTests",
            dependencies: ["Voco"],
            path: "TypelessTests"
        )
    ]
)
