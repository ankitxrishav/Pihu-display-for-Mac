// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PihuDisplayHost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "pihu-display-host", targets: ["PihuDisplayHost"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CGVirtualDisplayPrivate",
            path: "Sources/CGVirtualDisplayPrivate"
        ),
        .executableTarget(
            name: "PihuDisplayHost",
            dependencies: ["CGVirtualDisplayPrivate"],
            path: "Sources/PihuDisplayHost"
        )
    ]
)
