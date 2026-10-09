// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MallKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MallCore", targets: ["MallCore"]),
        .library(name: "MallData", targets: ["MallData"]),
        .library(name: "MallDesignSystem", targets: ["MallDesignSystem"]),
        .library(name: "CatalogFeature", targets: ["CatalogFeature"]),
        .library(name: "CartFeature", targets: ["CartFeature"]),
    ],
    targets: [
        .target(name: "MallCore"),
        .target(name: "MallData", dependencies: ["MallCore"], resources: [.process("Resources")]),
        .target(name: "MallDesignSystem"),
        .target(name: "CatalogFeature", dependencies: ["MallCore", "MallDesignSystem"]),
        .target(name: "CartFeature", dependencies: ["MallCore", "MallDesignSystem"]),
        .testTarget(name: "MallCoreTests", dependencies: ["MallCore"]),
        .testTarget(
            name: "MallDataTests", dependencies: ["MallData", "MallCore"],
            resources: [.process("Resources")]),
        .testTarget(name: "CatalogFeatureTests", dependencies: ["CatalogFeature", "MallCore"]),
        .testTarget(name: "CartFeatureTests", dependencies: ["CartFeature", "MallCore"]),
    ],
    swiftLanguageModes: [.v6]
)
