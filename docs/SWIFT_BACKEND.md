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
[tree-sitter-swift revision 28fe3a8](https://github.com/alex-pinkus/tree-sitter-swift/commit/28fe3a8a85586aa297524fe6164140b9521dcaff),
which includes the post-0.7.3 fix for `try await` in control-flow conditions.
The generated C parser, scanner, and required headers are packaged in our separate
[tree-sitter-swift-spm](https://github.com/swift-student/tree-sitter-swift-spm) repository.
The generated parser is approximately 20 MiB of source. File checksums, the upstream
commit, generator version, license, and reproduction instructions are in that package's
[provenance](https://github.com/swift-student/tree-sitter-swift-spm/blob/21736defb28d3ac25aaf053bd8eb6a5ecd8b49ce/Vendor/tree-sitter-swift/PROVENANCE.md).
SourceSymbols pins its packaging commit; consumers need no parser generator or
separate binary installation. See [grammar dependencies](GRAMMARS.md).

`SwiftAsyncControlFlowTests` covers `try`, `try?`, and `try!` combined with `await`
in `if`, `guard`, `while`, and `switch`. It checks clean diagnostics, qualified
names, declaration ranges, and methods after async packet loops. The grammar fix
keeps statement bodies from being consumed as trailing closures; no source rewriting
or declaration-recovery workaround is used in this adapter.

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

## Source-backed declaration headers

`headerRange` comes from a declaration's direct syntax children, stopping before
`function_body`, `computed_property`, `willset_didset_block`,
`protocol_property_requirements`, or the type/protocol/enum member body. It ends
after the last non-trivia header child. Nested braces in attributes, parameter
defaults, and stored initializers cannot become body boundaries. Attributes,
modifiers, failability, generic syntax, and interior comments remain source text;
the adapter does not format or reconstruct them from `CallableSignature`.

Bodyless declarations use the complete declaration syntax. Stored initializers
(including closures), aliases, associated types, and enum associated/raw values
remain in headers. All names in a grouped declaration share its header. A group
with another binding after an accessor has nil headers because the desired text
would require disjoint ranges. Protocol accessor requirements are excluded just
like implementation accessors. See [the API contract](API.md#source-backed-headers).

Missing/error nodes in the header make the range unavailable; errors confined to
the body preserve the header. No declaration/header is synthesized when recovery
leaves only loose tokens. `header-comment-recovery.swift` records another valid
source grammar gap: a block comment between a computed property's type and opening
brace disconnects its accessor syntax from the property. The recovered property
still supplies `var computed: Int`; the parser diagnostics remain visible. A header
is evidence of the recovered syntax boundary, not of Swift compiler acceptance.

Issue #15 adds `headers.swift` (overloads, multiline generics, typed throws,
attributes/defaults with braces, properties, type/extension headers, grouped enum
cases, bodyless declarations, and Unicode) and `header-groups.swift` (interior
comments and a deliberately invalid observer group). Exact source-authored slices
and offsets are checked in `DeclarationHeaderTests.swift`, including LF/CRLF copies,
snapshot identity, unknown headers, and independent matching metadata. The compiled
example prints two distinct overload headers with no consumer text parsing.

Local `make check` passed on 2026-09-14 with Swift 6.4 on macOS: 64 Swift Testing
tests, builds/example, zero lint violations, and clean formatting. The main header
fixture and comment regression were accepted by Swift's frontend parser; the
observer group intentionally produces a compiler diagnostic despite a clean
Tree-sitter parse. This does not add backend or platform support claims.

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
