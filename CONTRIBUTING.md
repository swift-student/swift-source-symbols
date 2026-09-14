# Contributing

This library uses Swift 6 language mode, Swift Testing, and
macOS 13 as its deployment minimum. Current local validation uses Swift 6.4 on
macOS; Swift 6.0 compiler compatibility and iOS/Linux support are not yet verified.

Install SwiftLint **0.65.1** and SwiftFormat **0.62.1** from their upstream tagged
releases, and place their executables on PATH. `make tools` verifies exact versions;
CI installs these same releases with verified SHA-256 checksums. Tool installation is maintainer setup and
is not required by library consumers. The Tree-sitter runtime dependency is pinned
in Package.swift; the grammars are vendored with [Swift provenance](Vendor/tree-sitter-swift/PROVENANCE.md),
[Ruby provenance](Vendor/tree-sitter-ruby/PROVENANCE.md),
[Kotlin provenance](Vendor/tree-sitter-kotlin/PROVENANCE.md), and
[TypeScript/TSX provenance](Vendor/tree-sitter-typescript/PROVENANCE.md).

- `make build`: compile the library and example.
- `make test`: run Swift Testing contract tests.
- `make lint`: validate the intentional lint rule set.
- `make format`: apply formatting.
- `make format-check`: reject formatting violations without editing source.
- `make example`: run the in-memory API example.
- `make check`: perform all validation above, without formatting source.

Commit the root Package.resolved when dependencies are introduced, to reproduce
maintainer and CI builds. Library consumers resolve their own dependency graph;
the root lockfile does not pin their builds. The current runtime resolution is committed.

Keep downloaded tools in ignored `.tools/`, scratch artifacts in `.cache/`, and
build output in `.build/`. Never commit credentials, downloaded toolchains, editor
state, or machine-specific paths. Intentional test fixtures under Fixtures retain
exact bytes, including CRLF. Check `git status --short` after validation.

Changes should explain behavior, validation, and limitations. Preserve API
boundaries described in docs/API.md and docs/ARCHITECTURE.md. Core tests import
`SourceSymbolsCore` without a parser dependency; integration tests use the consumer
`SourceSymbols` import. Reuse the backend contract helpers for additional languages,
and keep syntax fixtures and language-specific assertions independently specified.
Backward compatibility is not required until
the first proper release; breaking API changes are welcome when they improve the design.

## Continuous integration

Every pull request and push to `main` runs `make -k check` on macOS 15 with
Xcode 16.2 (Swift 6.0) and Xcode 26.2 (Swift 6.2). The `-k` flag reports independent
build, test, lint, formatting, and example failures while retaining a failing exit
status. Stable check names are `macOS / Swift 6.0` and `macOS / Swift 6.2`;
keep these names stable when configuring branch protection. Superseded runs are
cancelled, and matrix jobs finish independently.

The matrix checks the compiler baseline and a newer compiler with a macOS 13
deployment target. It does not run on macOS 13 itself and does not validate iOS
or Linux. Local Swift 6.4 validation remains separate from the hosted matrix.

Only pinned tool binaries are cached, keyed by OS, architecture, Xcode version,
installer/Makefile, and package manifests/lockfile. Build output and credentials
are not cached. Failure artifacts contain only toolchain, tool installation, and
`make check` logs, retained for seven days. Compiler diagnostics can include
relevant source excerpts; no source tree or build directory is uploaded.

Action SHAs resolve to the release tags recorded beside each `uses` entry.
When updating tools, update `Makefile` and `scripts/ci/install-tools.sh` together,
verify release asset digests against upstream metadata, and run the installer
and `make check`. Runner/Xcode availability comes from the official
[runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
