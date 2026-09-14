# Declaration corpus

The issue #6 corpus consists of original, intentionally small Swift sources, not
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

Issue #13 adds `enum-associated-values.swift` and `callable-scopes.swift`, with
source-authored JSON expectations for lexical scopes, lookup names, and exact byte
ranges. `enum-associated-labels.swift` covers explicit and escaped underscore
labels plus nested type/default punctuation. `lookup-recovery.swift` retains damaged
associated-value and callable headers alongside healthy siblings and bodies.
`enum-underscore-label.swift` retains a valid-source grammar false positive:
`case value(_: Int)` is base-name searchable but has no reliable signature.
The new valid-source fixtures were accepted by Swift 6.4's frontend on 2026-09-14;
`lookup-recovery.swift` is intentionally malformed.

JSON files specify expected declarations independently of the extractor: logical
name, kind, lexical scope names, and zero-based half-open UTF-8 identifier and full
declaration ranges. `qualifiedNames` independently specifies lookup paths, which
can differ from joined lexical scopes; the issue #13 JSON also specifies callable
and qualified callable names. They also specify expected diagnostic ranges; an empty list
means a clean parse is expected. Never regenerate expectations from backend output
to make a regression pass. Inspect source bytes and the public contract instead.
Additional expectations, including callable metadata and recovery, live in
TreeSitterSwiftExtractorTests.swift and SwiftLookupTests.swift. Unsupported syntax is listed in
[the backend decision](../../../../docs/SWIFT_BACKEND.md).

The issue #6 `.swift` fixtures except `incomplete*.swift` were accepted by Swift 6.4's frontend
parser on 2026-09-13. This is syntactic validity, not successful typechecking: some
fixtures intentionally reference undeclared types or duplicate overloads/branches.
Tree-sitter still reports known false-positive diagnostics for `block-comment.swift`
and `conditional.swift`. They remain valid-source regressions, not invalid Swift.

`unicode-crlf.swift` is the exact CRLF counterpart of `unicode-lf.swift`; preserve
the original bytes, emoji, decomposed accent, and identifier escaping. Git attributes
and both formatting tools exclude fixtures from normalization. Never run a formatter
over these files. Incomplete syntax and known grammar gaps must remain reproducible.

`source-link-navigation-lf.swift` preserves the in-memory lookup source from
[Source Link PR #14's tests at `8fede125`](https://github.com/swift-student/source-link/blob/8fede125a61747c2671b31f7e188f2ed32061430/Packages/SourceLinkPackage/Tests/SourceLinkCoreTests/SwiftSymbolTests.swift).
`source-link-navigation-crlf.swift` is its exact CRLF counterpart; neither has a
trailing newline. `SourcePositionIntegrationTests.swift` retains that consumer's
expected navigation lines and Unicode column, with additional columns specified
from source bytes. These fixtures retain the known block-comment false positive;
matching declarations and converting their positions does not suppress diagnostics.

The original Ruby corpus lives in [Ruby](Ruby/README.md), with separate language
expectations and the same snapshot/range/matching contract helpers.
