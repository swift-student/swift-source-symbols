# Grammar dependencies

SourceSymbols builds all grammar code from version-pinned SwiftPM source packages.
Generated parsers live in those packages, outside this repository. The public
`SourceSymbols` product still includes every backend, sharing one directly used
Tree-sitter runtime. No parser generator, language interpreter, or download outside
SwiftPM is required during consumer builds.

| Component | Package | Exact package version | Grammar/runtime upstream commit |
| --- | --- | --- | --- |
| Runtime | [tree-sitter/tree-sitter](https://github.com/tree-sitter/tree-sitter) | 0.25.10 | `da6fe9beb4f7f67beb75914ca8e0d48ae48d6406` |
| Swift | [swift-student/tree-sitter-swift-spm](https://github.com/swift-student/tree-sitter-swift-spm) | `0.1.1` | `28fe3a8a85586aa297524fe6164140b9521dcaff` |
| Ruby | [tree-sitter/tree-sitter-ruby](https://github.com/tree-sitter/tree-sitter-ruby) | 0.23.1 | `71bd32fb7607035768799732addba884a37a6210` |
| Kotlin | [tree-sitter-grammars/tree-sitter-kotlin](https://github.com/tree-sitter-grammars/tree-sitter-kotlin) | 1.1.0 | `77dd60ea0a9003ce062c9728a513ffe1aaff8c82` |
| TypeScript / TSX | [tree-sitter/tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) | 0.23.2 | `f975a621f4e7f532fe322e13c4f79495e0a7b2e7` |

`Package.resolved` records the actual package commits, including the separate Swift
packaging commit. Consumers resolve their own graph; this repository's lockfile
does not pin a consumer's transitive dependencies.

Swift package version 0.1.1 contains upstream's post-0.7.3
fix for `try await` in control-flow conditions. The previous grammar could consume
the body as a trailing closure, losing enclosing declarations and qualified names.
Our source-only package generates ABI 15 output from the unmodified upstream revision
with Tree-sitter CLI 0.25.10 and records each packaged file's checksum.
Its [provenance](https://github.com/swift-student/tree-sitter-swift-spm/blob/0.1.1/Vendor/tree-sitter-swift/PROVENANCE.md)
and regeneration script reproduce the parser and run upstream's complete parser corpus.
It supplies no runtime or queries; consumer builds need no generator.

The other grammars use upstream manifests and sources directly. Their manifests
also declare `SwiftTreeSitter` for upstream tests and copy query resources. Our
adapters use the grammar C modules and call the separately pinned `TreeSitter`
runtime directly; they do not import that wrapper or read query resources.

All five upstream projects use the MIT license. Preserve the applicable notices
when distributing their compiled code:
[runtime](https://github.com/tree-sitter/tree-sitter/blob/v0.25.10/LICENSE),
[Swift](https://github.com/swift-student/tree-sitter-swift-spm/blob/0.1.0/LICENSE),
[Ruby](https://github.com/tree-sitter/tree-sitter-ruby/blob/v0.23.1/LICENSE),
[Kotlin](https://github.com/tree-sitter-grammars/tree-sitter-kotlin/blob/v1.1.0/LICENSE),
and [TypeScript/TSX](https://github.com/tree-sitter/tree-sitter-typescript/blob/v0.23.2/LICENSE).

## Updates

1. Inspect the selected upstream release, generated parser ABI, license, and package
   manifest. For Swift, update and validate the separate packaging repository first;
   never hand-edit generated C files.
2. Change the exact version in `Package.swift`, resolve dependencies, and update
   this provenance table and `Package.resolved`.
3. Run `make check`, retaining the existing syntax, overload, recovery, Unicode,
   CRLF, and snapshot-bound range fixtures. Inspect changed diagnostics rather than
   normalizing them away.
4. Validate a consumer build and the configured CI toolchain matrix before making
   corresponding compatibility claims. Ensure local SwiftPM mirrors are removed
   before validating the published dependencies.

Using source packages changes repository ownership and update mechanics; their
compiled parser tables still contribute to the final application size.

## Migration validation

On 2026-09-14, `make check` passed locally with Swift 6.4 on macOS arm64:
98 Swift Testing tests, builds/example, zero lint violations, and clean formatting.
Checksums for the parser C sources, scanners, supporting headers, and licenses
matched the previously vendored copies. The standalone Swift package also passed
its checksum, debug/release build, lint, and formatting checks.

Swift 6.4 resolved only the five packages listed above; it did not fetch the
upstream test-only `SwiftTreeSitter` dependency. The release linker map contained
one directly used Tree-sitter runtime and all five grammar entry points.
The stripped example measured 12,590,248 bytes, versus 12,590,232 bytes before the
migration with the same toolchain and architecture. Upstream query bundles totaled
10,257 bytes of file contents. The migration removed 76,080,994 bytes of vendored
files from the source tree; it does not rewrite existing Git history.

These measurements do not establish other toolchain or platform support.
After publishing Swift package 0.1.0, the local mirrors were removed and all 98
tests and `make check` passed using the GitHub dependency. A separate consumer
built in release mode with a fresh build directory and successfully extracted
Swift, Ruby, Kotlin, TypeScript, and TSX declarations through `import SourceSymbols`.
The standalone grammar package's [Swift 6.0 and 6.2 CI jobs](https://github.com/swift-student/tree-sitter-swift-spm/actions/runs/34863926929)
also passed on macOS. SourceSymbols runs its own full fixture suite in the PR's CI matrix.
