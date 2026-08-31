// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MLXTrait",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MLXTrait", targets: ["MLXTrait"])],
    dependencies: [
        // The same package, same floor, is declared in project.yml. Bump both
        // together; `mise run generate` refuses to run while they disagree.
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "3.1.0", traits: ["MLX"]),
    ],
    targets: [
        .target(name: "MLXTrait", dependencies: [
            .product(name: "Title", package: "desert-ant-core"),
        ]),
    ]
)
