# API contract

SourceSymbols operates on immutable in-memory `SourceSnapshot` values with an
explicit `SourceLanguage` enum containing `.swift` and `.ruby`. Each newly
initialized snapshot has a unique identity; copies retain that identity.
The package has one public product and consumer import, `SourceSymbols`, bundling
the available backends. Shared models and matching live in the parser-independent
`SourceSymbolsCore` target; language adapters live in `SourceSymbols`. See
[the architecture](ARCHITECTURE.md) for the boundary and the next-language checklist.
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

`TreeSitterSwiftExtractor` and `TreeSitterRubyExtractor` implement the synchronous,
throwing, `Sendable` `DeclarationExtractor` protocol. They parse text directly as
UTF-8 using Tree-sitter Swift 0.7.3 or Ruby 0.23.1 and runtime 0.25.10.
Each extractor accepts only its corresponding language. Each call creates and disposes its own
parser/tree; it may be called concurrently. No backend pointer escapes in a result.
The input length is checked against Tree-sitter's 32-bit byte limit before parsing.

A `Declaration` contains a short name, qualified name, kind, optional structured
callable signature, outer-to-inner named lexical scopes, identifier range, and
full declaration range. Backends supply short, qualified, and optional callable
lookup spellings. The core compares those strings exactly; it does not choose
qualification separators or synthesize callable names from parameter metadata.
The following extraction and qualification conventions describe the Swift adapter.
Identifier ranges retain spelling, including backticks;
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

`CallableSignature` is syntactic metadata rather than a semantic callable identity.
Its ordered parameters contain a local binding `name`, an external `argumentLabel`,
optional `typeSyntax`, a `passing` style, and `hasDefaultValue`. Names and labels are
independent: Swift's `value local: Int` has name `local` and label `value`, while
`_ local: Int` has name `local` and a nil label. A nil name means there is no single
named binding, for example Swift's `ignored _: Int`. A nil type means no annotation
is present, not an inferred type or a wildcard. Backends with damaged headers
should omit the entire signature instead of representing damaged types as absent.

Passing styles are positional, keyword, variadic positional, variadic keyword, and
block. Positional parameters may have labels; Swift's ordered labeled arguments
remain positional. Ruby keyword, rest, and block parameters use their respective
passing styles. Default expressions are excluded, but their presence is
recorded. Exact signature equality includes all parameter fields, including local
names, passing styles, and default presence. Use a callable-name or parameter-type
query when those extra distinctions are irrelevant.

Optional generic parameter syntax, generic constraints, effects, and return type
remain backend-defined syntax. The Swift adapter retains `async`, `throws`,
`rethrows`, typed throws, generic parameter and `where` clauses. Swift parameter
types include attributes, ownership modifiers, and a variadic suffix when present.
Syntax strings exclude surrounding trivia but retain interior trivia. There is no
whitespace, type-alias, or semantic normalization; `Int` and `Swift.Int` remain
distinct. Static/instance modifiers, declaration attributes, and initializer
failability are not represented, so some declarations may still remain ambiguous.

`name`/`qualifiedName` omit parameter lists. `callableName` and
`qualifiedCallableName` are supplied by the backend. The Swift adapter adds external
labels, for example `run(value:)` and `Store.run(value:)`, rendering a nil label as
`_`. Operator and subscript parameters without an explicit external label have nil
labels. Swift non-callables and callables with an unreliably recovered header have
no callable name/signature. The core permits a signature without callable aliases;
providing metadata alone never invents a new lookup spelling.
A body error alone does not discard a sound header's signature.

`DeclarationQuery` matches short or qualified names, accepting either the base
name or the callable name. Optional `parameterTypes: [String?]?` narrows by the
complete, ordered annotation list. A nil list omits the filter; `[nil]` requires
exactly one parameter with no annotation; `[]` requires a known zero-parameter
signature. A nil signature never satisfies an annotation filter. Optional
`signature` compares all structured metadata exactly. Supplied filters are combined.
Matching is case-sensitive and returns
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

## Ruby extraction and lookup

Use `SourceSnapshot(text: sourceText, language: .ruby)` with
`TreeSitterRubyExtractor`. Classes and modules are `type` declarations; method
syntax (including `initialize`) and static aliases are `method`; singleton class
bodies are `extensionScope`; constant assignment candidates are `variable`.
Repeated definitions and reopened classes remain distinct, in traversal order.

Namespace paths use `::`, instance methods use `#`, and singleton methods use `.`:
`Shop::Cart`, `Shop::Cart#add`, and `Shop::Cart.build`. Lexical scopes remain separate
from these lookup strings. Absolute paths retain leading `::`. Constant lookup,
visibility, and receiver dispatch are not evaluated. Ruby supplies no extra callable
aliases; queries use the base names with optional structured signature filters.
Receiver-rooted constant paths use the same conventions as method receivers:
inside `Cart`, `self::Nested` qualifies as `Cart::Nested` while retaining
`self::Nested` as the class or module's lexical scope component.

Ruby parameter annotations are nil. Positional/defaulted, keyword, rest, keyword
rest, and block parameters retain names, passing styles, and default presence.
Anonymous `*`, `**`, and `&` parameters retain their channel with a nil name.
Forwarding (`...`), destructuring, and keyword rejection (`**nil`) are not fully
represented by the shared model, so those methods have nil signatures. Aliases
also have nil signatures because their targets are not resolved.

Ruby ranges include delayed heredoc bodies through the closing delimiter. Comments
outside declarations are excluded. A visibility call such as `private def run; end`
contributes no token to the method's range, which begins at `def`. See the
[Ruby backend contract](RUBY_BACKEND.md) for exact qualification examples, recovery,
coverage, and omitted dynamic declarations.

## Diagnostics and limitations

Tree-sitter `ERROR` and missing-token nodes produce error-severity `ParseDiagnostic`
values alongside available declarations. Errors in hidden grammar tokens are reported
at the nearest visible node when it has no exposed erroneous child. Diagnostics may be zero-width and may
include overlapping parent/child error ranges. Nodes with missing or erroneous
names are skipped; a damaged callable header has a nil signature. A successful
match does not imply a clean parse. These are backend parse diagnostics, not language
compiler/type-checker diagnostics, and known grammar false positives are preserved.
`ExtractionResult` rejects declaration or diagnostic ranges from other snapshots.

Unsupported languages throw `ExtractionError.unsupportedLanguage`; fatal backend
setup/parse failures throw `TreeSitterExtractionError`. A clean parser result does
not guarantee that every declaration category is extracted. See the tested syntax
and known gaps in the [Swift backend decision](SWIFT_BACKEND.md) and
[Ruby backend contract](RUBY_BACKEND.md).

The package uses Swift tools 6.0, Swift 6 language mode, and a macOS 13 deployment
minimum. Both backends have been locally validated with Swift 6.4 on macOS 26.6.2
(arm64). The configured Swift 6.0/6.2 CI matrix still needs to run against these
changes; macOS 13 runtime, iOS, and Linux are not validated. SourceKitten execution
and a SwiftSyntax comparison were intentionally deferred in the issue #6 discussion.
UI, URLs, editor launching, file loading, Git snapshots, and anchor relocation
belong in consumer adapters. Backward compatibility is not required before the
first proper release.
