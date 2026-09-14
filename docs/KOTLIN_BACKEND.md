# Kotlin backend contract

`TreeSitterKotlinExtractor` accepts `.kotlin` snapshots and parses UTF-8 in memory.
It uses [tree-sitter-grammars/tree-sitter-kotlin 1.1.0](https://github.com/tree-sitter-grammars/tree-sitter-kotlin/releases/tag/v1.1.0)
(language ABI 14) with the existing Tree-sitter runtime 0.25.10. The C grammar is
vendored separately with its [license, commit, and checksums](../Vendor/tree-sitter-kotlin/PROVENANCE.md).
Consumers need neither Kotlin/JVM nor a parser generator. Each extraction owns its
parser and tree; the extractor is Sendable and can be reused concurrently.

## Declarations and lookup

| Syntax | Kind and representation |
| --- | --- |
| Classes, interfaces, annotation/data/value classes, named objects | `type` |
| Companion objects | `type`; unnamed companions use `Companion`, with the `object` keyword as their identifier range |
| Functions in a class/object/enum-entry member body | `method` |
| Top-level and local functions | `function` |
| Top-level/member `val` and `var`, including delegated and extension properties | `property` |
| Local `val` and `var` | `variable` |
| Primary-constructor `val`/`var` parameters | Separate `property` declarations spanning the parameter syntax |
| Secondary constructors | `initializer` named `constructor`, with the keyword as identifier |
| `init` blocks | `initializer` named `init`, with the keyword as identifier; no callable signature |
| Enum entries | `enumCase`, including entries with arguments and member bodies |
| Type aliases | `typeAlias` |

The primary constructor's signature is attached to the class declaration; it is
not emitted again with a fabricated source identifier. A class with no written
parameter list has a nil signature; `class Empty()` has a known zero-parameter
signature. Plain constructor/function parameters are metadata, not declarations.
Destructuring property declarations emit each named binding in source order with
the same full/header range. An unescaped `_` is skipped.

Qualification uses dots and includes the file's package: `shop.Cart.add`.
Package segments are not lexical scope components or separate declarations.
Identifier ranges retain backticks; lookup names remove them. Extension receivers
are included before the base name: `sample.List<T>.choose`, `sample.String.render`,
and `sample.Int.render`. Receiver/package lookup spelling concatenates syntax tokens,
omitting trivia and identifier backticks. Generic arguments and nullable markers
remain part of receiver paths. No import, type-alias, dispatch, inherited-member,
companion forwarding, or project-wide name resolution is performed.

Named lexical scopes include types, functions, constructors, enum entries, and
individual property initializers/accessors. An extension function's lexical
component is its base name even though its lookup path includes the receiver.
Anonymous blocks, lambdas, and object expressions add no component; object member
bodies still classify their members as methods/properties. Destructuring initializers
have no single named owner. Separate blocks and repeated/overloaded declarations
can have identical lookup paths; every candidate remains in traversal order.
Kotlin does not provide additional callable aliases. Use base names with exact
parameter-type or structured-signature filters.

## Signatures and headers

Parameters retain their local name and the same name as `argumentLabel`, ordered
annotation syntax, default presence, and positional or variadic-positional (`vararg`)
passing. This is syntax metadata, not a claim that every call site can use named
arguments. Function types, nullable/generic types, and interior comments/whitespace
are preserved. Defaults are excluded from metadata. Generic parameters, `where`
constraints, explicit return types, and `suspend` are retained; inferred return types
are nil. Receiver types affect lookup paths, not the shared signature, so short-name
signature filters can remain ambiguous across receivers. Other modifiers and
annotations remain available in the source-backed header, not signature equality.

Full ranges start at the first declaration token, including attributes/modifiers,
and end at the last available token. Surrounding comments/whitespace are excluded.
Headers exclude member bodies, function block/expression bodies (including `=`),
constructor/init blocks, and property accessors. Constructor delegation calls stay
in the header. Stored/delegated property initializers and enum arguments stay in
headers; enum member bodies do not. Nested braces in annotations/defaults/lambdas
do not delimit the surrounding declaration's header.

All ranges are snapshot-bound, zero-based, half-open UTF-8 bytes, with no Unicode
or newline normalization. The shared UTF-16 conversions and SourcePositionIndex
apply unchanged. Header errors make headers and callable signatures unavailable;
recognized body errors preserve a sound header. Matching never suppresses diagnostics.

## Coverage and limitations

The independent [Kotlin corpus](../Tests/SourceSymbolsTests/Fixtures/Kotlin/README.md)
checks exact byte ranges, declaration order and kinds, qualification, overloads,
headers, annotations, generic/nullable/function types, constructors, nested scopes,
objects, enum bodies, strings and comments, malformed syntax, Unicode, LF/CRLF,
NUL recovery, language rejection, and concurrent calls. Local `make check` validation
uses Swift 6.4 on macOS 26.6.2 (arm64), in Swift 6 language mode. The configured
Swift 6.0/6.2 CI matrix is separate; macOS 13 runtime, iOS, and Linux are not validated.

This is a syntactic declaration extractor, not a Kotlin compiler or an exhaustive
Kotlin-version compatibility claim. Loop/catch/lambda parameter bindings, synthetic
data-class members, accessor declarations, imports, and package declarations are
not emitted. Context receivers/parameters and other newer syntax are not validated.
No declaration is rebuilt from loose tokens when recovery loses its syntax node.

Known pinned-grammar behavior is preserved in tests:

- `class Compact { fun run() {} }` produces a hidden member-separator error on the
  class body, even though both declarations and their sound headers are available.
  Similar compact constructs can recover more broadly and lose declarations.
- An unfinished class/function can lose those ancestor nodes while retaining a
  property candidate; its original enclosing scopes cannot then be recovered.
- A standalone NUL causes the remaining source to become one ERROR through the
  actual EOF. The original snapshot and diagnostic range retain all bytes, but
  declarations after that NUL may be unavailable.

Missing-token, ERROR, and hidden-recovery diagnostics remain visible. A clean parse
or unique match does not imply semantic validity or complete extraction coverage.
