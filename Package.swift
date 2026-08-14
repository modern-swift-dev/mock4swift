// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Mocksmith",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "Mocksmith", targets: ["Mocksmith"]),
        .library(name: "MocksmithCombine", targets: ["MocksmithCombine"]),
        .library(name: "MocksmithTesting", targets: ["MocksmithTesting"]),
        .library(name: "MocksmithXCTest", targets: ["MocksmithXCTest"]),
        .plugin(name: "MocksmithBuildPlugin", targets: ["MocksmithBuildPlugin"])
    ],
    dependencies: [
        .package(path: "Tests/Fixtures/external-protocols"),
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            exact: "603.0.2"
        )
    ],
    targets: [
        .macro(
            name: "MocksmithMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
            ]
        ),
        .target(name: "Mocksmith", dependencies: ["MocksmithMacros"]),
        .target(name: "MocksmithCombine", dependencies: ["Mocksmith"]),
        .target(name: "MocksmithTesting", dependencies: ["Mocksmith"]),
        .target(name: "MocksmithXCTest", dependencies: ["Mocksmith"]),
        .target(
            name: "MocksmithInheritanceFixture",
            dependencies: ["Mocksmith"],
            plugins: ["MocksmithBuildPlugin"]
        ),
        .executableTarget(
            name: "MocksmithGenerator",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .plugin(
            name: "MocksmithBuildPlugin",
            capability: .buildTool(),
            dependencies: ["MocksmithGenerator"]
        ),
        .testTarget(name: "MocksmithRuntimeTests", dependencies: ["Mocksmith"]),
        .testTarget(
            name: "MocksmithCombineTests",
            dependencies: ["Mocksmith", "MocksmithCombine"]
        ),
        .testTarget(
            name: "MocksmithMacrosTests",
            dependencies: [
                "MocksmithMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "MocksmithIntegrationTests",
            dependencies: [
                "Mocksmith",
                "MocksmithTesting",
                "MocksmithXCTest",
                "MocksmithInheritanceFixture",
                .product(name: "ExternalProtocols", package: "external-protocols")
            ],
            plugins: ["MocksmithBuildPlugin"]
        ),
        .testTarget(
            name: "MocksmithSamples",
            dependencies: ["Mocksmith", "MocksmithTesting", "MocksmithXCTest"],
            path: "samples/Tests",
            plugins: ["MocksmithBuildPlugin"]
        )
    ],
    swiftLanguageModes: [.v6]
)
