// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DotAssist",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "DotAssist", targets: ["DotAssist"]),
    ],
    targets: [
        .target(name: "DotAssist", path: "Sources/DotAssist"),
        .testTarget(
            name: "DotAssistTests",
            dependencies: ["DotAssist"],
            path: "Tests/DotAssistTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
