# SourceSymbols

A Swift library for extracting and matching source declarations across languages.

Status: initial SwiftPM API scaffold with contract tests and a runnable fixture example. No bundled production parser or released package yet.

The intended API accepts source text and returns declaration names, signatures, enclosing scopes, and precise source ranges. Extraction and matching remain independent of UI, URLs, editor launching, and Git review snapshots. Initial language candidates are Swift, TypeScript/TSX, Ruby, and Kotlin.

A local comparison favored direct SwiftTreeSitter over wrapping Tree-sitter Tags: both needed the same qualification and signature logic. The Swift backend remains undecided pending broader coverage and investigation of grammar errors; see [#6](../../issues/6).

## Setup backlog

1. [Swift 6 package and public API](../../issues/1)
2. [Gitignore and contributor conventions](../../issues/2)
3. [SwiftLint, SwiftFormat, and make check](../../issues/3)
4. [GitHub Actions CI](../../issues/4)
5. [Parser and query packaging](../../issues/5)
6. [Fixtures and Swift backend evaluation](../../issues/6)
7. [Documentation and support](../../issues/7)
8. [Repository protection and releases](../../issues/8)

Start with #1–#3, then CI. Parser packaging and backend evaluation inform the implementation and support policy. Configure required checks after CI is passing.

## Local development

Run `make check` with Swift and the pinned tools described in
[CONTRIBUTING.md](CONTRIBUTING.md). Run `swift run UsageExample` for the compiled
in-memory extraction/matching example in [Examples/main.swift](Examples/main.swift).
The example uses a fixed fixture adapter, not a production parser.

The library product and importable module are both `SourceSymbols`. For local
consumer experiments, add `.package(path: "../swift-source-symbols")` to your
SwiftPM dependencies and `.product(name: "SourceSymbols", package: "swift-source-symbols")`
to the consuming target. There is no released version to install.

See [the API decision](docs/API.md) for ranges, snapshot lifetime, matching, parse
diagnostics, and platform limitations. Current validation is Swift 6.4 on macOS;
Swift 6 language mode and macOS 13 deployment minimum are declared. iOS and Linux
are not yet validated. No general extraction languages or file extensions are
supported until a production backend is integrated.
