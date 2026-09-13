# API contract

SourceSymbols operates on immutable in-memory `SourceSnapshot` values with an
explicit `SourceLanguage` enum, currently containing only Swift. Each newly
initialized snapshot has a unique identity; copies retain that identity.
`SourceRange` values can only be constructed by their snapshot and contain
zero-based UTF-8 byte offsets with an exclusive upper bound. Empty ranges,
including EOF, are valid. Offsets must fall on Unicode scalar boundaries; they
may divide a composed grapheme. CRLF occupies two bytes. Text is never newline-
or Unicode-normalized, and a range remains meaningful only for its original
snapshot, never for edited text.

`range(utf16Offsets:)` and `utf16Offsets(for:)` convert zero-based half-open UTF-16
ranges. They reject out-of-bounds offsets, boundaries inside surrogate pairs, and
ranges belonging to another snapshot. A boundary between CR and LF is valid in
both encodings. Line/column and editor-specific adapters remain consumer work.

## Extraction and ranges

`TreeSitterSwiftExtractor` implements the synchronous, throwing, `Sendable`
`DeclarationExtractor` protocol. It parses Swift text directly as UTF-8 using
Tree-sitter Swift 0.7.3 and runtime 0.25.10. Each call creates and disposes its own
parser/tree; it may be called concurrently. No backend pointer escapes in a result.
The input length is checked against Tree-sitter's 32-bit byte limit before parsing.

A `Declaration` contains a short name, qualified name, kind, optional structured
callable signature, outer-to-inner named lexical scopes, identifier range, and
full declaration range. Identifier ranges retain spelling, including backticks;
lookup names remove identifier backticks. Extension names concatenate the extended
type's syntax tokens, removing intervening trivia and identifier escaping, so
`extension Host . Inner` qualifies members under `Host.Inner`. Extensions have
kind `extensionScope`, not `type`; both may match the same qualified name.
These are per-file syntactic results, not project-wide or type-checked identities.

Full declaration ranges begin at the first syntactic token (including attributes
and modifiers) and end after the last available syntactic token. Leading comments,
documentation comments, whitespace, and trailing comments/whitespace are excluded.
Interior comments remain part of the contiguous range. For a recovered declaration,
the end is the last available source token; missing syntax is never invented.
Each name in a multi-binding `let`/`var` or enum case group shares the group's full
range. The identifier is always contained in the declaration.

Named scopes include types, extensions, callables, and individual property/variable
initializers and accessors. A tuple binding's shared initializer has no single name
and contributes no scope component. Anonymous closures and control-flow blocks
contribute no name. Local declarations in separate anonymous blocks or overloads
can consequently have the same qualified name; all remain available. Method and
property kinds apply in a type's member context; functions/variables inside bodies,
initializers, and accessors are local. Results follow syntax traversal order:
parents before descendants, sibling nodes and grouped bindings in source order.

## Callable matching

`CallableSignature` replaces the initial backend-defined string signature. It
contains parameters (external argument label and exact type syntax), optional
generic parameter and `where` clauses, effects (`async`, `throws`, `rethrows`,
including typed throws), and optional return type. Parameter type syntax includes
type attributes, modifiers such as `inout`, and a variadic suffix when present.
Default values and local parameter names are not part of the signature. Syntax
strings exclude surrounding trivia but retain interior trivia; no whitespace,
type-alias, or semantic normalization is performed. For example, `Int` and
`Swift.Int` remain distinct. This metadata is not an exhaustive callable identity:
static/instance modifiers, declaration attributes, and initializer failability are
not signature filters. Such declarations remain separate and may remain ambiguous.

`name`/`qualifiedName` omit parameter lists. `callableName` and
`qualifiedCallableName` add external labels, for example `run(value:)` and
`Store.run(value:)`. `_` denotes an unlabeled argument. Operator parameters and
subscript parameters without an explicit external label use `_`. Non-callables
and callables with an unreliably recovered header have no callable name/signature.
A body error alone does not discard a sound header's signature.

`DeclarationQuery` matches short or qualified names, accepting either the base
name or the callable name. Optional `parameterTypes` narrows by the complete,
ordered type-syntax list. Optional `signature` compares the structured metadata
exactly. Supplied filters are combined. Matching is case-sensitive and returns
`missing`, `unique`, or every `ambiguous` candidate in input order. No fuzzy
matching, deduplication, or arbitrary overload selection occurs.

```swift
let snapshot = SourceSnapshot(text: sourceText, language: .swift)
let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
let match = DeclarationMatcher.match(
    .init(name: .qualified("Store.run(value:)"), parameterTypes: ["Int"]),
    in: result.declarations
)
// Independently inspect result.diagnostics, even when match is unique.
```

## Diagnostics and limitations

Tree-sitter `ERROR` and missing-token nodes produce error-severity `ParseDiagnostic`
values alongside available declarations. Errors in hidden grammar tokens are reported
at the nearest visible node when it has no exposed erroneous child. Diagnostics may be zero-width and may
include overlapping parent/child error ranges. Nodes with missing or erroneous
names are skipped; a damaged callable header has a nil signature. A successful
match does not imply a clean parse. These are backend parse diagnostics, not Swift
compiler/type-checker diagnostics, and known grammar false positives are preserved.
`ExtractionResult` rejects declaration or diagnostic ranges from other snapshots.

Unsupported languages throw `ExtractionError.unsupportedLanguage`; fatal backend
setup/parse failures throw `TreeSitterExtractionError`. A clean parser result does
not guarantee that every declaration category is extracted. See the tested syntax
and known gaps in [the backend decision](SWIFT_BACKEND.md).

The package uses Swift tools 6.0, Swift 6 language mode, and a macOS 13 deployment
minimum. This backend has been locally validated with Swift 6.4 on macOS 26.6.2
(arm64). The configured Swift 6.0/6.2 CI matrix still needs to run against these
changes; macOS 13 runtime, iOS, and Linux are not validated. SourceKitten execution
and a SwiftSyntax comparison were intentionally deferred in the issue #6 discussion.
UI, URLs, editor launching, file loading, Git snapshots, and anchor relocation
belong in consumer adapters. Backward compatibility is not required before the
first proper release.
