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
        .library(name: "MallImages", targets: ["MallImages"]),
    ],
    dependencies: [.package(url: "https://github.com/kean/Nuke.git", exact: "13.2.0")],
    targets: [
        .target(name: "MallCore"),
        .target(name: "MallData", dependencies: ["MallCore"], resources: [.process("Resources")]),
        .target(name: "MallDesignSystem"),
        .target(
            name: "CatalogFeature", dependencies: ["MallCore", "MallDesignSystem", "MallImages"]),
        .target(name: "CartFeature", dependencies: ["MallCore", "MallDesignSystem"]),
        .target(
            name: "MallImages",
            dependencies: [
                .product(name: "Nuke", package: "Nuke"), .product(name: "NukeUI", package: "Nuke"),
            ]),
        .testTarget(
            name: "MallImagesTests",
            dependencies: ["MallImages", .product(name: "Nuke", package: "Nuke")],
            resources: [.process("Resources")]),
        .testTarget(name: "MallCoreTests", dependencies: ["MallCore"]),
        .testTarget(
            name: "MallDataTests", dependencies: ["MallData", "MallCore"],
            resources: [.process("Resources")]),
        .testTarget(name: "CatalogFeatureTests", dependencies: ["CatalogFeature", "MallCore"]),
        .testTarget(name: "CartFeatureTests", dependencies: ["CartFeature", "MallCore"]),
    ],
    swiftLanguageModes: [.v6]
)
