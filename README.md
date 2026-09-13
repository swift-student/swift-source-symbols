# SourceSymbols

A Swift library for extracting and matching source declarations across languages.

Status: initial Tree-sitter Swift extractor with a permanent declaration corpus and a runnable in-memory example. No released package yet.

The API accepts source text and returns declaration names, structured callable signatures, enclosing scopes, diagnostics, and precise source ranges. Extraction and matching remain independent of UI, URLs, editor launching, and Git review snapshots. Initial language candidates are Swift, TypeScript/TSX, Ruby, and Kotlin.

The initial Swift backend uses direct Tree-sitter syntax-node traversal. See the [backend decision](docs/SWIFT_BACKEND.md) for tested syntax, permanent grammar regressions, dependency provenance, and the deferred SourceKitten/SwiftSyntax comparisons.

## Setup backlog

1. [Swift 6 package and public API](../../issues/1)
2. [Gitignore and contributor conventions](../../issues/2)
3. [SwiftLint, SwiftFormat, and make check](../../issues/3)
4. [GitHub Actions CI](../../issues/4)
5. [Parser and query packaging](../../issues/5)
6. [Fixtures and Swift backend evaluation](../../issues/6)
7. [Documentation and support](../../issues/7)
8. [Repository protection and releases](../../issues/8)

The package foundation and CI are in place. Parser packaging and the documented backend decision inform the remaining support and release work.

## Local development

Run `make check` with Swift and the pinned tools described in
[CONTRIBUTING.md](CONTRIBUTING.md). Run `swift run UsageExample` for the compiled
in-memory extraction/matching example in [Examples/main.swift](Examples/main.swift).
The example extracts two real overloads and selects one by its argument label and parameter type.

The library product and importable module are both `SourceSymbols`. For local
consumer experiments, add `.package(path: "../swift-source-symbols")` to your
SwiftPM dependencies and `.product(name: "SourceSymbols", package: "swift-source-symbols")`
to the consuming target. There is no released version to install.

See [the API decision](docs/API.md) for ranges, snapshot lifetime, matching, parse
diagnostics, and platform limitations. Current validation is Swift 6.4 on macOS;
Swift 6 language mode and macOS 13 deployment minimum are declared. iOS and Linux
are not yet validated. Swift extraction is limited to the syntax covered by the
[backend decision](docs/SWIFT_BACKEND.md); other languages are not implemented.
