// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SourceSymbols",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SourceSymbols", targets: ["SourceSymbols"])],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/tree-sitter", exact: "0.25.10"),
    ],
    targets: [
        .target(name: "SourceSymbolsCore"),
        .target(name: "TreeSitterSwiftGrammar", path: "Vendor/tree-sitter-swift",
                exclude: ["LICENSE", "PROVENANCE.md", "SHA256SUMS"],
                sources: ["src/parser.c", "src/scanner.c"], publicHeadersPath: "include",
                cSettings: [.headerSearchPath("src")]),
        .target(name: "TreeSitterRubyGrammar", path: "Vendor/tree-sitter-ruby",
                exclude: ["LICENSE", "PROVENANCE.md", "SHA256SUMS"],
                sources: ["src/parser.c", "src/scanner.c"], publicHeadersPath: "include",
                cSettings: [.headerSearchPath("src")]),
        .target(name: "TreeSitterKotlinGrammar", path: "Vendor/tree-sitter-kotlin",
                exclude: ["LICENSE", "PROVENANCE.md", "SHA256SUMS"],
                sources: ["src/parser.c", "src/scanner.c"], publicHeadersPath: "include",
                cSettings: [.headerSearchPath("src")]),
        .target(name: "TreeSitterTypeScriptGrammar", path: "Vendor/tree-sitter-typescript",
                exclude: ["LICENSE", "PROVENANCE.md", "SHA256SUMS"],
                sources: ["typescript/src/parser.c", "typescript/src/scanner.c",
                          "tsx/src/parser.c", "tsx/src/scanner.c"], publicHeadersPath: "include",
                cSettings: [.headerSearchPath("typescript/src")]),
        .target(name: "SourceSymbols", dependencies: [
            "SourceSymbolsCore", "TreeSitterSwiftGrammar", "TreeSitterRubyGrammar", "TreeSitterKotlinGrammar",
            "TreeSitterTypeScriptGrammar",
            .product(
                name: "TreeSitter",
                package: "tree-sitter"
            ),
        ]),
        .executableTarget(name: "UsageExample", dependencies: ["SourceSymbols"], path: "Examples"),
        .testTarget(name: "SourceSymbolsCoreTests", dependencies: ["SourceSymbolsCore"]),
        .testTarget(name: "SourceSymbolsTests", dependencies: ["SourceSymbols"],
                    resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
