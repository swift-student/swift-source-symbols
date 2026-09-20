// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SourceSymbols",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SourceSymbols", targets: ["SourceSymbols"])],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/tree-sitter", exact: "0.25.10"),
        .package(url: "https://github.com/swift-student/tree-sitter-swift-spm",
                 exact: "0.1.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-kotlin", exact: "1.1.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", exact: "0.23.2"),
    ],
    targets: [
        .target(name: "SourceSymbolsCore"),
        .target(name: "SourceSymbols", dependencies: [
            "SourceSymbolsCore",
            .product(name: "TreeSitter", package: "tree-sitter"),
            .product(name: "TreeSitterSwiftGrammar", package: "tree-sitter-swift-spm"),
            .product(name: "TreeSitterRuby", package: "tree-sitter-ruby"),
            .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin"),
            .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
        ]),
        .executableTarget(name: "UsageExample", dependencies: ["SourceSymbols"], path: "Examples"),
        .testTarget(name: "SourceSymbolsCoreTests", dependencies: ["SourceSymbolsCore"]),
        .testTarget(name: "SourceSymbolsTests", dependencies: ["SourceSymbols"],
                    resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
