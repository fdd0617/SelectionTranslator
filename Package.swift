// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SelectionTranslator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SelectionTranslator", targets: ["SelectionTranslator"])
    ],
    targets: [
        .executableTarget(name: "SelectionTranslator"),
        .testTarget(name: "SelectionTranslatorTests", dependencies: ["SelectionTranslator"])
    ]
)
