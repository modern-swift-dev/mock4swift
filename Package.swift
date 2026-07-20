// swift-tools-version:6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "mock-4-swift",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "mock4swift",
            targets: ["mock4swift"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "mock4swift"
        ),

        .testTarget(
            name: "mock4swift-tests",
            dependencies: [
                "mock4swift"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
