// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenTypeLess",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "OpenTypeLess", targets: ["OpenTypeLess"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "OpenTypeLess",
            dependencies: [],
            path: "Typeless"
        ),
        .testTarget(
            name: "TypelessTests",
            dependencies: ["OpenTypeLess"],
            path: "TypelessTests"
        )
    ]
)
