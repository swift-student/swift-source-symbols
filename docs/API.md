# API contract

SourceSymbols operates on immutable in-memory `SourceSnapshot` values with an
explicit `SourceLanguage` enum containing `.swift`, `.ruby`, and `.kotlin`. Each newly
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
both encodings. Generic line/column conversion is available through the core's
`SourcePositionIndex`; editor-specific adapters remain consumer work.

## Source positions

Build `SourcePositionIndex(snapshot:)` once and reuse it for positions in that
immutable snapshot. `position(in:at:columnEncoding:)` converts a `SourceRange`'s
`.start` (the default) or `.end` (the exclusive upper bound). Foreign-snapshot
ranges return nil, including ranges from a new snapshot with identical text.
Snapshot copies retain identity and are accepted. `position(atUTF8Offset:columnEncoding:)`
interprets a zero-based byte offset in the indexed snapshot; negative, out-of-bounds,
and scalar-interior offsets return nil without clamping. EOF is valid.

`SourcePosition` retains the snapshot ID, canonical UTF-8 offset, selected column
encoding, and **one-based** `line` and `column`. Select `.utf8` for byte columns or
`.utf16` for UTF-16 code-unit columns. For example, 😀 contributes four UTF-8 bytes and two
UTF-16 code units; a combining scalar contributes separately, and tabs count as one
code unit without visual expansion. These are source coordinates, not display widths.
No conversion changes the canonical zero-based, half-open UTF-8 range model.

LF, lone CR, and CRLF each terminate a line. A position before a line terminator is
at the end of that line. The valid boundary **between CR and LF** stays on the
preceding line, with CR contributing one column; the next line begins after LF.
Other Unicode separators are ordinary scalars. Empty input has position `(1, 1)`;
a trailing terminator creates an empty final line whose EOF column is 1. EOF without
a trailing terminator is just after the final scalar on the last line. Source bytes,
including newline spelling and Unicode normalization, are preserved.

Construction makes one pass over the source and stores line starts and multibyte
scalar spans. Storage is proportional to the number of lines plus non-ASCII scalars;
each lookup uses binary searches over those two tables, without rescanning source
text. Index copies share immutable storage, and the index is `Sendable` for concurrent
lookups. It retains its original snapshot identity even after a consumer edits text;
create a new snapshot and index for the edited source.

```swift
let positions = SourcePositionIndex(snapshot: result.snapshot)
if let position = positions.position(in: declaration.identifierRange, columnEncoding: .utf16) {
    // One-based line and UTF-16 column, as needed by Source Link.
    print(position.line, position.column)
}
```

The compiled `UsageExample` demonstrates this with an extracted identifier.
Position conversion does not inspect or suppress extraction diagnostics.

## Extraction and ranges

`TreeSitterSwiftExtractor`, `TreeSitterRubyExtractor`, and `TreeSitterKotlinExtractor` implement the synchronous,
throwing, `Sendable` `DeclarationExtractor` protocol. They parse text directly as
UTF-8 using Tree-sitter Swift 0.7.3, Ruby 0.23.1, or Kotlin 1.1.0 and runtime 0.25.10.
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

Named lexical scopes include types, extensions, callables, and individual property/variable
initializers and accessors. A tuple binding's shared initializer has no single name
and contributes no scope component. Anonymous closures and control-flow blocks
contribute no name. Lexical scope components retain base names, independently of
lookup paths. For example, a function nested in `Host.outer(value:)` has
`enclosingScopes == ["Host", "outer"]` while its qualified lookup path includes
`outer(value:)`. Local declarations in separate anonymous blocks or overloads
with identical labels can consequently have the same qualified name; all remain
available. Method and property kinds apply in a type's member context; functions/variables inside bodies,
initializers, and accessors are local. Results follow syntax traversal order:
parents before descendants, sibling nodes and grouped bindings in source order.

## Source-backed headers

`Declaration.headerRange` is an optional source range, independent of the identifier,
full declaration range, and structured `signature`. Retrieve its original text with
`snapshot.text(in: headerRange)`. It is bound to the same immutable snapshot,
contained in `declarationRange`, and contains `identifierRange`; the declaration
initializer rejects foreign or improperly nested ranges. All existing UTF-8,
UTF-16, and source-position rules apply. Nil explicitly means the backend cannot
provide a reliable contiguous header under its conventions, not an empty header.

Headers start at the first declaration token and end after the last header token.
Leading documentation, trailing comments/whitespace, and body delimiters are
excluded. Interior whitespace, comments, Unicode, and LF/CRLF bytes remain exact.
Boundaries come from syntax nodes; braces nested in attributes, default expressions,
or closure types do not delimit declaration bodies. Consumers control whitespace
presentation, truncation, qualification/context labels, and styling.

| Backend / declaration | Header convention |
| --- | --- |
| Swift functions, initializers, deinitializers, subscripts | Excludes the function/accessor body; retains attributes, modifiers, generic syntax, labels/local names, annotations, defaults, effects, return syntax, constraints, and initializer `?`/`!` |
| Swift types, protocols, extensions | Excludes the member body; retains inheritance and constraints |
| Swift computed/observed properties and protocol property requirements | Excludes the accessor, observer, or `{ get set }` block |
| Swift stored bindings, type aliases, associated types, enum cases, bodyless callables | Whole declaration syntax, including stored initializer expressions, raw values, and associated values |
| Swift grouped bindings and enum cases | Each name shares the group's header; nil if an accessor precedes further bindings, since excluding it would require disjoint ranges |
| Ruby methods, including singleton, bare-parameter, and endless forms | `def` through the parameter list or method name; excludes the body, separating `;`/`=`, and `end`; visibility wrappers are outside the declaration |
| Ruby classes, modules, singleton classes | Through the namespace path, superclass expression, or singleton receiver; excludes member bodies and `end` |
| Ruby static aliases | Whole alias declaration |
| Ruby constant assignments | Nil: the adapter does not define a separate header for initializer-only declarations |
| Ruby headers containing heredocs | Nil: delayed default/superclass/receiver text cannot reliably form one contiguous header without body syntax |

A stored Swift closure initializer remains part of its binding's header; it can be
large. Ruby methods with heredocs only in their implementation retain their header.
Ruby forwarding, destructuring, keyword rejection, and aliases can have exact headers
even though their structured signatures are unavailable. Conversely, a Ruby heredoc
default can have structured metadata while its source-backed header is unavailable.
Neither header availability nor header text affects matching.

Missing or erroneous header syntax makes the header unavailable. Errors confined
to a recognized body do not invalidate a sound header, including a missing closing
body delimiter. Recovery can change declaration boundaries or omit a declaration
entirely; the backend never rebuilds a header from loose tokens. Parse diagnostics
remain independently available, even for declarations with headers and unique matches.

```swift
if case let .ambiguous(choices) = DeclarationMatcher.match(
    .init(name: .qualified("Store.refresh(force:)")), in: result.declarations
) {
    for choice in choices {
        if let header = choice.headerRange {
            print(snapshot.text(in: header) ?? "")
            // e.g. "func refresh(force: Bool)" or "func refresh(force: Int)"
        }
    }
}
```

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

`name` omits parameter lists. `qualifiedName` omits the declaration's own parameter
list, but the Swift adapter uses label-bearing names for every enclosing callable.
For example, a nested function has `name == "inner"`,
`qualifiedName == "Host.outer(value:).inner"`, `callableName == "inner()"`, and
`qualifiedCallableName == "Host.outer(value:).inner()"`. A nested variable uses
`Host.outer(value:).local` and has no callable alias. This convention also applies
through nested types, property initializers/accessors, initializers, subscripts,
and deinitializers; zero-parameter callable scope components include `()`.
The previous `Host.outer.inner()` spelling is not an additional alias.

`callableName` and `qualifiedCallableName` are supplied by the backend. The Swift
adapter adds external labels, for example `run(value:)` and `Store.run(value:)`,
rendering a nil label as `_`. Operator and subscript parameters without an explicit
external label have nil labels. Enclosing overloads with different labels produce
distinct paths; those sharing labels remain ambiguous even if their parameter
types differ. Query signature/type filters apply only to the declaration being
matched, not to its enclosing callables. An enclosing callable with an unreliably
recovered header contributes its base name as a fallback, with diagnostics retained.
Swift non-callables and callables with an unreliably recovered header have
no callable name/signature. The core permits a signature without callable aliases;
providing metadata alone never invents a new lookup spelling.
A body error alone does not discard a sound header's signature.

Associated-value enum cases retain kind `enumCase` and provide callable aliases
and signatures: `case payload(value: Int)` matches both `Event.payload` and
`Event.payload(value:)`; `case pair(Int, text: String)` adds `pair(_:text:)`.
Each case in a comma-separated group owns its own signature while retaining the
shared full declaration range and its own identifier range. Parameters record
labels, type syntax, positional passing, and default presence. Their binding
`name` is nil because associated-value declarations introduce no local bindings;
return types and enclosing enum generic syntax are not inferred. Ordinary and
raw-value cases have no signature or parenthesized alias. A damaged associated-value
list has no signature/alias; healthy sibling cases can still have them.

Swift parameters are deliberately **not independently navigable declarations**.
Function, initializer, subscript, closure, and enum associated-value parameters
do not add declaration results, identifier ranges, or named lexical scopes.
Callable parameter bindings remain available as signature metadata where supported;
`Host.outer(value:).value` does not navigate to the parameter. A separately declared
local variable remains navigable. This policy does not add a parameter declaration
category based on incidental output from another backend.

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

## Kotlin extraction and lookup

Use `SourceSnapshot(text: sourceText, language: .kotlin)` with
`TreeSitterKotlinExtractor`. Package-prefixed lookup paths use dots, such as
`shop.Cart.add`. Extension receiver syntax is included in qualified names:
`sample.String.render` and `sample.Int.render`. Backticks remain in identifier
ranges and are removed from lookup names. There are no extra callable aliases;
overloads are narrowed using exact parameter-type or signature filters.

Kotlin extracts types, objects/companions, functions/methods, properties/local
variables (including `when` subject bindings), primary-constructor property parameters,
secondary constructors, init blocks, enum entries, and type aliases. Primary constructor metadata is attached
to the class declaration. Parameters retain names as argument labels, annotation
syntax, varargs, and defaults; signatures also retain generics, constraints,
explicit return types, and `suspend`.

Headers exclude class/function bodies and accessors, retaining stored/delegated
initializers, defaults, and constructor delegation syntax. Recovered header errors
make metadata unavailable, including initializer errors detached from property nodes;
body errors preserve sound headers. Receiver lookup paths retain annotations and
type modifiers such as `suspend`. See the
[Kotlin backend contract](KOTLIN_BACKEND.md) for exact scope/header conventions,
independently tested coverage, and pinned-grammar recovery limitations.

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
and known gaps in the [Swift backend decision](SWIFT_BACKEND.md),
[Ruby backend contract](RUBY_BACKEND.md), and [Kotlin backend contract](KOTLIN_BACKEND.md).

The package uses Swift tools 6.0, Swift 6 language mode, and a macOS 13 deployment
minimum. All three backends have been locally validated with Swift 6.4 on macOS 26.6.2
(arm64). The configured Swift 6.0/6.2 CI matrix still needs to run against these
changes; macOS 13 runtime, iOS, and Linux are not validated. SourceKitten execution
and a SwiftSyntax comparison were intentionally deferred in the issue #6 discussion.
Issue #13 records a later consumer-side comparison and adds regression coverage
for the lookup cases described above; full SourceKitten parity is not established.
UI, URLs, editor launching, file loading, Git snapshots, and anchor relocation
belong in consumer adapters. Backward compatibility is not required before the
first proper release.
