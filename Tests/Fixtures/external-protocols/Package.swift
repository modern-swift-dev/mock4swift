// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "external-protocols",
    products: [
        .library(name: "ExternalProtocols", targets: ["ExternalChildProtocols"])
    ],
    targets: [
        .target(name: "ExternalBaseProtocols"),
        .target(
            name: "ExternalChildProtocols",
            dependencies: ["ExternalBaseProtocols"]
        )
    ],
    swiftLanguageModes: [.v6]
)
