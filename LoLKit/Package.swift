// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LoLKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "LoLKit", targets: ["LoLKit"]),
    ],
    targets: [
        .target(name: "LoLKit"),
        .testTarget(
            name: "LoLKitTests",
            dependencies: ["LoLKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
