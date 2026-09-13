# SourceSymbols

A planned Swift library for extracting and matching source declarations across languages, shared by [Source Link](https://github.com/swift-student/source-link) and [DevCtrl](https://github.com/swift-student/devctrl).

Status: repository setup and API design. No released package or production implementation yet.

The intended API accepts source text and returns declaration names, signatures, enclosing scopes, and precise source ranges. Extraction and matching remain independent of UI, source-link URLs, editor launching, and Git review snapshots. Initial language candidates are Swift, TypeScript/TSX, Ruby, and Kotlin.

A local comparison favored direct SwiftTreeSitter over wrapping Tree-sitter Tags: both needed the same qualification and signature logic. The Swift backend remains undecided pending broader coverage and investigation of grammar errors; see [#6](../../issues/6).

## Setup backlog

1. [Swift 6 package and public API](../../issues/1)
2. [Gitignore and contributor conventions](../../issues/2)
3. [SwiftLint, SwiftFormat, and make check](../../issues/3)
4. [GitHub Actions CI](../../issues/4)
5. [Parser and query packaging](../../issues/5)
6. [Fixtures and Swift backend evaluation](../../issues/6)
7. [Documentation and licensing](../../issues/7)
8. [Repository protection and releases](../../issues/8)

Start with #1–#3, then CI. Parser packaging and backend evaluation inform the implementation and support policy. Configure required checks after CI is passing.

## Background

- [Source Link multi-language proposal](https://github.com/swift-student/source-link/issues/15)
- [Initial SourceKitten implementation](https://github.com/swift-student/source-link/pull/14)
