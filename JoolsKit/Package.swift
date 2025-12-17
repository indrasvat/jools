// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JoolsKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "JoolsKit",
            targets: ["JoolsKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "JoolsKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            path: "Sources/JoolsKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "JoolsKitTests",
            dependencies: ["JoolsKit"],
            path: "Tests/JoolsKitTests"
        ),
    ]
)
