# Swift backend decision — issue #6

Decision: use direct Tree-sitter syntax-node traversal as the initial Swift backend.
The scope agreed during issue #6 implementation is to validate Tree-sitter against
an independently specified declaration corpus, retain valid-source grammar
regressions, and defer both the executable SourceKitten baseline and the
SwiftParser/SwiftSyntax comparison. This is not a comparative claim that Tree-sitter
is more correct than either alternative, nor a claim of SourceKitten parity.
Revisit the deferred comparison if a grammar gap prevents useful navigation.
Issue #13 later recorded a Source Link comparison for specific lookup cases. The
regressions below address those cases without establishing full SourceKitten parity.

## Implementation and reproducibility

The runtime is [Tree-sitter v0.25.10](https://github.com/tree-sitter/tree-sitter/releases/tag/v0.25.10),
pinned exactly in Package.swift and recorded in Package.resolved. The grammar is
[tree-sitter-swift 0.7.3](https://github.com/alex-pinkus/tree-sitter-swift/releases/tag/0.7.3).
Its Git tag omits the generated parser, so the release archive's generated C parser,
scanner, and required headers are vendored without modification. The generated
parser is approximately 20 MiB of source. Archive/file checksums, tag commit,
upstream paths, license, and update instructions are in
[PROVENANCE.md](../Vendor/tree-sitter-swift/PROVENANCE.md). Consumers need no parser
generator or separate binary installation. No claim about consumer build cost or
binary size is made without measurement.

The small Swift adapter calls the C runtime directly, reads UTF-8 offsets, and
walks declaration nodes. It uses neither a Swift wrapper dependency nor Tree-sitter
Tags. This avoids the prototype's whole-class-as-method query capture problem;
member ranges are asserted independently from their enclosing type ranges.
Parameter structure comes from syntax nodes/tokens, never regexes or comma-based
signature parsing. The pinned generated grammar reuses the `name` field for some
types, so parameter types are located after the parameter's direct colon token and
return types after the callable's direct arrow token, including separate annotation and suffix nodes. Nested type/default-expression
punctuation is never treated as a callable-level separator.

The adapter lives in `Sources/SourceSymbols/Swift` and supplies its own qualified
and callable lookup spellings. Parser-independent models and matching live in
`SourceSymbolsCore`, exposed through the single `SourceSymbols` consumer module.
Parameter metadata retains local names separately from optional argument labels,
records default presence, and classifies Swift variadics. See
[the architecture](ARCHITECTURE.md) for the shared Swift/Ruby boundary.

Associated-value enum cases provide positional signatures with labels, type syntax,
and default presence, but nil local binding names. Each name in a grouped entry is
paired with its own following `enum_type_parameters` node. Only that node's direct
comma tokens separate values, so tuple/function/generic types and default-expression
commas cannot split a value. Ordinary/raw-value cases retain base names and no signature.

Swift qualification uses an enclosing callable's label-bearing name whenever its
header is sound: `Host.outer(value:).inner()` and `Host.outer(text:).inner()` are
distinct paths. The declaration's `qualifiedName` omits only its own argument list;
`qualifiedCallableName` includes it. Lexical `enclosingScopes` still stores
`["Host", "outer"]`. The adapter tracks lexical and lookup components separately,
and supplies no legacy base-name scope alias. Same-label enclosing overloads and
separate anonymous blocks can still produce ambiguous paths. A damaged enclosing
header contributes its base name, preserving available declarations and diagnostics.

Parameters are metadata, not independently navigable declarations. This includes
callable bindings, closure parameters, and enum associated values. They add no
declaration category, identifier range, or scope component. Query filters describe
the target declaration's signature, never the enclosing callable's signature.

## Corpus and observed behavior

The permanent [fixtures](../Tests/SourceSymbolsTests/Fixtures) are original test
sources with independently specified names, kinds, scopes, and UTF-8 ranges in
JSON. Swift Testing compares every extracted declaration against those expectations,
with additional structured-signature, matching, recovery, and range assertions.
Fixture loading belongs only to the tests. Production extraction takes in-memory
snapshots. The LF/CRLF pair is protected from Git newline conversion and formatting.

| Coverage | Observed result with pinned backend |
| --- | --- |
| Struct/class, protocol, enum, nested types, type aliases, associated types, enum cases | Expected declarations and byte ranges |
| Short/qualified names; overloads with different labels and identical labels | All candidates preserved; optional type/signature filters narrow matches |
| Associated-value enum cases, grouped cases, labels, nested types/defaults, escaped names | Per-case callable aliases/signatures; shared full ranges and distinct identifier ranges |
| Nested declarations through labeled callables, initializers, subscripts, deinitializers | Canonical label-bearing paths; lexical scopes retain base names; same-label overloads remain ambiguous |
| Callable and associated-value parameters | Metadata only; no independent parameter declaration navigation |
| Properties, comma/tuple bindings, computed properties, local functions/variables | Expected names, shared declaration ranges, and named scopes |
| Extensions, including dotted and escaped names | Separate extension scopes; correctly qualified members |
| Attributes, modifiers, documentation and interior/trailing comments | Full ranges include attributes/modifiers and interior trivia only |
| Generic functions and constraints, closure parameter types/defaults, tuples, variadics, inout, effects, typed throws | Expected structured signatures |
| Operator functions, init/deinit, labeled/unlabeled subscripts | Expected names, labels, and ranges |
| Emoji, non-ASCII, decomposed identifiers, escaped identifiers, LF and CRLF | Exact UTF-8 ranges and scalar-safe UTF-16 round trips |
| Conditional compilation | Declarations from every branch; one known false-positive diagnostic in fixture |
| Incomplete syntax, missing tokens, embedded NUL | Available declarations plus diagnostics; input is not truncated at NUL |
| Representative in-memory navigation index | Expected nested declarations, scopes, and byte ranges |
| Concurrent independent snapshots | Per-call parser/tree lifetime and snapshot identities preserved |

## Known gaps

1. `block-comment.swift` preserves the original valid Swift reproducer:
   `struct A {}` followed by `/* comment */ struct B {}` on the next line. Both
   declarations are recovered, but Tree-sitter reports an error. Moving the comment
   to its own line gives a clean result in `block-comment-own-line.swift`. The
   diagnostic is not suppressed. Keep both sources even if an upstream fix requires
   updating the diagnostic expectation.
2. `conditional.swift` is also valid Swift but produces a zero-width error at UTF-8
   offset 106, at the first directive inside `Container`. All expected branch
   declarations survive. This fixture records that diagnostic explicitly. No build
   conditions are evaluated, so mutually exclusive declarations can be ambiguous.
3. Recovery is best-effort syntax recovery. Malformed input can omit declarations or
   change their apparent nesting. Names with parse errors/missing tokens are omitted;
   damaged callable headers have no signature. Hidden-token errors are reported at
   their nearest visible erroneous node, even when another error exists elsewhere
   in the file. Diagnostics are always retained.
4. Extraction is limited to the declaration categories in the adapter/corpus. Macro
   declarations/expansion, operator and precedence-group declarations, synthesized
   members, accessor declarations as separate symbols, and project-wide semantic
   resolution are not implemented. Typechecking, import resolution, inferred types,
   compiler conditional-branch selection, and canonical type identities are outside
   this per-file contract.
5. Signature metadata is not an exhaustive identity. Static/instance modifiers,
   declaration attributes, and initializer failability are not query filters. Exact
   syntax comparisons can distinguish equivalent type spellings or formatting;
   unmatched or ambiguous results are returned without guessing.
6. Performance on large or adversarial input and incremental parsing are not
   validated. Extraction currently reparses each immutable snapshot in full.
7. `enum-underscore-label.swift` is accepted by Swift 6.4's frontend, but the pinned
   grammar recovers a missing identifier for `case value(_: Int)`. The case retains
   its base name and ranges, with a diagnostic and no signature/alias. Unlabeled
   `case value(Int)`, explicit `case value(_ name: Int)`, and escaped underscore
   labels are covered separately. This grammar gap is not hidden by synthesizing a
   signature from an erroneous header.

## Issue #13 validation on 2026-09-14

`make check` passed locally with Swift 6.4 on macOS 26.6.2 (arm64): 57 Swift Testing
tests, library/example builds, zero lint violations, and clean formatting.
`enum-associated-values.swift` and `callable-scopes.swift` have source-authored JSON
expectations for every declaration, lexical scope, lookup spelling, and UTF-8 range.
`SwiftLookupTests.swift` additionally asserts enum signature/type filters, matching
and ambiguity, parameter exclusion, LF/CRLF Unicode ranges, and recovery in
`lookup-recovery.swift`. `enum-associated-labels.swift` covers explicit/escaped
underscore labels, annotated types, interior trivia, and nested default punctuation.
The new valid-source fixtures, including the underscore-only grammar regression,
were accepted by Swift 6.4's frontend parser. This establishes syntactic validity
only; overload fixtures need not typecheck. No new backend or platform parity claim
is made.

## Validation recorded on 2026-09-13

Local environment: Apple Swift 6.4 (`swiftlang-6.4.0.33.1`), Swift 6 language mode,
macOS 26.6.2, arm64. `make check` builds the library and real extraction example,
runs Swift Testing, and checks pinned lint/format tools. The valid `.swift` fixtures
were also individually accepted by `swiftc -frontend -parse`; this includes the
block-comment and conditional false positives. The incomplete fixture is excluded
from that valid-source check. Frontend parsing establishes syntactic validity only;
it is not a SourceKitten extraction baseline or a SwiftSyntax backend comparison.

The existing CI jobs target Swift 6.0 and Swift 6.2 on macOS. They have not yet
validated this change. macOS 13 runtime, iOS, and Linux support are not claimed.
Parser/query distribution follow-up remains tracked separately in issue #5.
