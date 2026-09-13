# Contributor instructions

Use Swift 6 language mode and Swift Testing. Keep extraction, matching, and source
position handling independent of consumer UI, URLs, editors, Git, and filesystem
loading. Do not introduce a regex-based production parser. Preserve overloads,
ambiguity, diagnostics, and snapshot-bound zero-based half-open UTF-8 ranges.

Run `make check` before proposing changes. `make format` edits handwritten Swift;
`make check` only validates. Keep fixtures for syntax and Unicode regressions.
Do not normalize intentionally preserved fixture line endings. Generated parsers
and vendored code must stay separate from handwritten code and carry provenance.

Backward compatibility is not required until the first proper release. Make
breaking API changes when they improve the design. No backend or platform support
claims without validation. See docs/API.md and CONTRIBUTING.md.
