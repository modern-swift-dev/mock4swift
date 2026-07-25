// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "mock-4-swift",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "Mock4Swift", targets: ["Mock4Swift"]),
        .library(name: "Mock4SwiftTesting", targets: ["Mock4SwiftTesting"]),
        .library(name: "Mock4SwiftXCTest", targets: ["Mock4SwiftXCTest"]),
        .plugin(name: "Mock4SwiftBuildPlugin", targets: ["Mock4SwiftBuildPlugin"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            exact: "603.0.2"
        ),
    ],
    targets: [
        .macro(
            name: "Mock4SwiftMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .target(name: "Mock4Swift", dependencies: ["Mock4SwiftMacros"]),
        .target(name: "Mock4SwiftTesting", dependencies: ["Mock4Swift"]),
        .target(name: "Mock4SwiftXCTest", dependencies: ["Mock4Swift"]),
        .target(
            name: "Mock4SwiftInheritanceFixture",
            dependencies: ["Mock4Swift"],
            plugins: ["Mock4SwiftBuildPlugin"]
        ),
        .executableTarget(
            name: "Mock4SwiftGenerator",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .plugin(
            name: "Mock4SwiftBuildPlugin",
            capability: .buildTool(),
            dependencies: ["Mock4SwiftGenerator"]
        ),
        .testTarget(name: "Mock4SwiftRuntimeTests", dependencies: ["Mock4Swift"]),
        .testTarget(
            name: "Mock4SwiftMacrosTests",
            dependencies: [
                "Mock4SwiftMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "Mock4SwiftIntegrationTests",
            dependencies: ["Mock4Swift", "Mock4SwiftTesting", "Mock4SwiftXCTest", "Mock4SwiftInheritanceFixture"],
            plugins: ["Mock4SwiftBuildPlugin"]
        ),
        .testTarget(
            name: "Mock4SwiftSamples",
            dependencies: ["Mock4Swift", "Mock4SwiftTesting", "Mock4SwiftXCTest"],
            path: "samples/Tests",
            plugins: ["Mock4SwiftBuildPlugin"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
