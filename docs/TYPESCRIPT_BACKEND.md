# TypeScript / TSX backend contract

`TreeSitterTypeScriptExtractor` is bundled in `SourceSymbols`. It accepts
`.typescript` and `.tsx` snapshots, selecting the corresponding Tree-sitter 0.23.2
grammar (language ABI 14) with runtime 0.25.10. Use `.typescript` for declaration
files too. Each call owns its parser and tree; extraction is synchronous, Sendable,
and entirely in memory. There is no filename detection, module loader, TypeScript
compiler, Node.js dependency, or parser generation in consumer builds.

The unmodified generated parsers, scanners, headers, MIT license, upstream commit,
and shipped-file hashes are recorded in
[the vendored grammar provenance](../Vendor/tree-sitter-typescript/PROVENANCE.md).
The existing parser ownership utilities are shared with Swift and Ruby; all
TypeScript syntax, trivia, scope, range, and recovery policy lives in
`Sources/SourceSymbols/TypeScript`.

## Declarations and lookup

| Syntax | Kind | Example lookup |
| --- | --- | --- |
| Classes (including abstract), interfaces, enums | `type` | `App.Client`, `App.Store`, `App.State` |
| Namespaces and ambient modules | `extensionScope` | `App.Tools`, `"remote"` |
| Type aliases | `typeAlias` | `App.Item` |
| Functions, generator functions, overload/ambient signatures | `function` | `App.choose` |
| Class, interface, direct object-type and object-literal methods | `method` | `App.Client.read` |
| Bare instance constructors in class bodies | `initializer` | `App.Client.constructor` |
| Fields, property signatures, object properties, getters/setters | `property` | `App.Client.current` |
| Enum members | `enumCase` | `App.State.Ready` |
| `const`/`let`/`var` bindings, including destructuring and loop bindings | `variable` | `App.first`, `App.choose.local` |

Qualified names join lexical components with `.`. A dotted namespace retains its
whole path as one scope component: `namespace App.Tools` has short name `Tools`,
qualified name `App.Tools`, and its children have `enclosingScopes == ["App.Tools"]`.
Trivia between namespace tokens is excluded from lookup spelling. String, numeric,
escaped-identifier, and private names retain source spelling, including quotes,
escapes, or `#`; no escape evaluation or Unicode normalization occurs. Quoted and
bare properties are consequently distinct lookup spellings even when JavaScript
would treat their runtime keys alike.

There are no `callableName` or `qualifiedCallableName` aliases. Queries use base
names with optional type/signature filters. Overload declarations and implementations,
merged interfaces/namespaces, same-name getters/setters, and repeated definitions
are preserved in syntax order. Static/instance status and receiver dispatch are not
resolved, so distinct declarations can remain ambiguous.

Named type/callable bodies contribute their name. Simple binding/property
initializers contribute the binding/property name, including arrow initializers.
A named function or class expression additionally contributes its explicit name:
`const factory = function inner() { const local = 1; }` produces `factory`,
`factory.inner`, and `factory.inner.local`. Anonymous classes, functions, closures,
and control-flow blocks add no synthetic name. Their descendants still use the
nearest named lexical scope; a method of an anonymous class remains a method.
Destructuring's shared initializer has no single binding scope. Grouped variables
are emitted before initializer descendants; otherwise parents precede descendants,
and siblings follow source order.

Destructuring includes actual binding identifiers through array/object patterns,
renaming, defaults, and rest patterns. Property keys and assignment references do
not become bindings. Parameters (including constructor parameter properties),
type parameters, imports/re-exports, and catch bindings are not independent results.
Direct members of an interface or an object-literal type alias are extracted;
arbitrary nested type expressions do not introduce navigable member scopes.

## Signatures and headers

Function/method/constructor declarations retain ordered parameter metadata.
Variables and properties directly initialized with an arrow, function, or generator
expression (optionally parenthesized) also have signatures while retaining their
binding kind. An annotation alone does not cause a variable to acquire a signature,
and expression types are never inferred.

- Binding names are local identifiers, with nil external labels. Destructured
  parameters have nil names; their binding pattern structure is not represented.
- Type syntax excludes the annotation colon and surrounding trivia, preserving
  interior whitespace/comments. Absent annotations are nil, including inferred
  arrow parameters and defaulted parameters without annotations.
- Rest parameters use `variadicPositional`; all other supplied parameters are
  positional. `isOptional` records `?`, separately from `hasDefaultValue` and any
  union with `undefined`. Existing Swift/Ruby parameters default to false.
- Type-parameter clauses retain their complete syntax, including `extends` and
  defaults. `genericConstraints` is nil because constraints are inside that clause.
  Return annotations retain types, predicates, or `asserts` syntax. Effects retain
  `async` and generator `*` in source order.
- An explicit `this` pseudo-parameter has no shared receiver channel, so its entire
  callable signature is nil. Its reliable source header remains available.

Exact signature matching compares represented metadata, including optionality;
annotation-only matching intentionally ignores optionality and default presence.
This is not TypeScript assignability or complete signature identity: method
optionality, parameter property modifiers, destructuring structure, decorators,
and static/visibility modifiers are not structured signature fields.

All ranges are snapshot-bound half-open UTF-8 byte offsets. Declaration ranges
include attached decorators and export/declare wrappers, beginning at the first
syntax token and ending at the last available one. Comments and whitespace outside
a declaration are excluded. Members exclude separators owned by their containing
body; statement declarations retain their own semicolon. Grouped variable bindings
share the entire declaration statement. A `for ... in/of` binding covers its
`const`/`let`/`var` token through its binding (and initializer if present), excluding
the iteration expression and body; assignment-only loop targets are omitted.

Headers start with the declaration and stop before the recognized body or trailing
separator. Type/function/method headers preserve decorators, wrappers, generics,
heritage, parameters/defaults, and return annotations. Stored bindings/properties,
aliases, and enum members retain initializer/value syntax in their header; grouped
bindings share that header. A closure initializer therefore can make a binding's
header large. Boundaries come from nodes, so nested braces in type annotations or
default expressions do not end a header. Interior trivia, combining scalars,
non-BMP characters, and LF/CRLF bytes remain unchanged.

## Recovery and limits

All Tree-sitter error and missing-token diagnostics are retained in tree order,
including syntax intentionally omitted from declaration extraction. A malformed
header loses both header and signature; healthy names remain queryable when a
declaration node survives. Errors confined to a recognized body preserve a sound
header/signature. No loose-token or regex fallback rebuilds lost declarations.
`incomplete.ts` records an unterminated class/method collapsing into one `ERROR`:
only its recoverable local variable remains, with no inferred enclosing names.

TSX parses JSX using the TSX grammar. JSX tags, attributes, and text do not create
declarations, while executable expressions retain nested declarations. Plain
TypeScript and TSX have different syntax ambiguities; choose the dialect explicitly.
No JSX component resolution or framework-specific behavior is inferred.

Computed member names (including `Symbol.iterator`), unnamed call/construct/index
signatures, import/re-export binding resolution, declaration merging, inheritance,
visibility, cross-file identity, and arbitrary callable-expression inference are
not implemented. Descendants of omitted computed methods keep their nearest
recoverable named scope. This is a tested syntax subset of the pinned grammar,
not a claim of complete TypeScript-version conformance; a clean parse does not
imply complete extraction or a type-correct program.

## Validation

The permanent [corpus](../Tests/SourceSymbolsTests/Fixtures/TypeScript/README.md)
checks independently authored declaration/diagnostic offsets in TypeScript and TSX,
matching ambiguity, optional/rest/default/destructured parameters, headers, scopes,
recovery, Unicode, CRLF, embedded NULs, and concurrent calls across both dialects.
Core matching tests distinguish optional, required, and defaulted parameters
without importing a parser. Existing Swift/Ruby tests remain in the full check.

Local validation uses Swift 6.4 in Swift 6 language mode on macOS 26.6.2 (arm64)
with `make check`. The configured Swift 6.0/6.2 CI matrix validates those toolchains
separately. macOS 13 runtime, iOS, Linux, and other toolchains are not locally
validated for this backend. Fixtures are parser contracts and are not a claim that
a TypeScript compiler has accepted their semantics.
