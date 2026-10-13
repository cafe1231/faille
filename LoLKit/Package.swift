// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LoLKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "LoLKit", targets: ["LoLKit"]),
        .executable(name: "lolkit", targets: ["lolkit-cli"]),
    ],
    targets: [
        .target(name: "LoLKit"),
        .executableTarget(name: "lolkit-cli", dependencies: ["LoLKit"]),
        .testTarget(
            name: "LoLKitTests",
            dependencies: ["LoLKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
