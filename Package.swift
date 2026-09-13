// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SourceSymbols",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SourceSymbols", targets: ["SourceSymbols"])],
    targets: [
        .target(name: "SourceSymbols"),
        .executableTarget(name: "UsageExample", dependencies: ["SourceSymbols"], path: "Examples"),
        .testTarget(name: "SourceSymbolsTests", dependencies: ["SourceSymbols"]),
    ],
    swiftLanguageModes: [.v6]
)
