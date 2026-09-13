# Contributing

This library uses Swift 6 language mode, Swift Testing, and
macOS 13 as its deployment minimum. Current local validation uses Swift 6.4 on
macOS; Swift 6.0 compiler compatibility and iOS/Linux support are not yet verified.

Install SwiftLint **0.65.1** and SwiftFormat **0.62.1** from their upstream tagged
releases, and place their executables on PATH. `make tools` verifies exact versions;
use these same versions when adding CI. Tool installation is maintainer setup and
is not required by library consumers. The package currently has no dependencies.

- `make build`: compile the library and example.
- `make test`: run Swift Testing contract tests.
- `make lint`: validate the intentional lint rule set.
- `make format`: apply formatting.
- `make format-check`: reject formatting violations without editing source.
- `make example`: run the in-memory API example.
- `make check`: perform all validation above, without formatting source.

Commit the root Package.resolved when dependencies are introduced, to reproduce
maintainer and CI builds. Library consumers resolve their own dependency graph;
the root lockfile does not pin their builds. No lockfile exists until needed.

Keep downloaded tools in ignored `.tools/`, scratch artifacts in `.cache/`, and
build output in `.build/`. Never commit credentials, downloaded toolchains, editor
state, or machine-specific paths. Intentional test fixtures under Fixtures retain
exact bytes, including CRLF. Check `git status --short` after validation.

Changes should explain behavior, validation, and limitations. Preserve API
boundaries described in docs/API.md. Backward compatibility is not required until
the first proper release; breaking API changes are welcome when they improve the design.
