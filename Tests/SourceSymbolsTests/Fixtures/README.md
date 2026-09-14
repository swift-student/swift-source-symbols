# Declaration corpus

These are original, intentionally small Swift sources authored for issue #6, not
copied from third-party applications. `representative.swift` models an in-memory
navigation index to exercise realistic nested/generic declarations and closures.
`block-comment.swift` preserves the exact source reproducer recorded in issue #6.
`tuple-bindings.swift` covers labeled and nested tuple patterns, wildcard initializer
scopes, and parenthesized single bindings. `incomplete-trivia.swift` retains trailing
comments after a missing brace; its range regression also runs with CRLF line endings.
`parameter-metadata.swift` distinguishes local names from argument labels, omitted
bindings, defaults, escaped names, and variadic parameter packs. Shared backend contract assertions live in
`../Support/BackendContract.swift`; language-specific spelling and signature checks
remain in the Swift tests.

JSON files specify expected declarations independently of the extractor: logical
name, kind, lexical scope names, and zero-based half-open UTF-8 identifier and full
declaration ranges. They also specify expected diagnostic ranges; an empty list
means a clean parse is expected. Never regenerate expectations from backend output
to make a regression pass. Inspect source bytes and the public contract instead.
Additional expectations, including callable metadata and recovery, live in
TreeSitterSwiftExtractorTests.swift. Unsupported syntax is listed in
[the backend decision](../../../../docs/SWIFT_BACKEND.md).

All `.swift` fixtures except `incomplete*.swift` were accepted by Swift 6.4's frontend
parser on 2026-09-13. This is syntactic validity, not successful typechecking: some
fixtures intentionally reference undeclared types or duplicate overloads/branches.
Tree-sitter still reports known false-positive diagnostics for `block-comment.swift`
and `conditional.swift`. They remain valid-source regressions, not invalid Swift.

`unicode-crlf.swift` is the exact CRLF counterpart of `unicode-lf.swift`; preserve
the original bytes, emoji, decomposed accent, and identifier escaping. Git attributes
and both formatting tools exclude fixtures from normalization. Never run a formatter
over these files. Incomplete syntax and known grammar gaps must remain reproducible.

The original Ruby corpus lives in [Ruby](Ruby/README.md), with separate language
expectations and the same snapshot/range/matching contract helpers.
