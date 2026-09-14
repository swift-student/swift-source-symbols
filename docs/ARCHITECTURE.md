# Architecture

SourceSymbols is one library product for projects containing multiple languages.
Consumers use `import SourceSymbols`; the product bundles every implemented backend.
There are no per-language product choices or external backend registration system.
Swift, Ruby, Kotlin, and TypeScript/TSX are implemented with explicit extractors.
The TypeScript extractor selects its grammar from `.typescript` or `.tsx`.

## Internal boundaries

- `Sources/SourceSymbolsCore` contains snapshots, ranges, reusable line/column indexes, declarations, callable
  metadata, diagnostics, the extractor protocol, and exact matching. This target
  depends only on Foundation and has no parser dependency.
- `Sources/SourceSymbols/Exports.swift` exposes the shared types through explicit
  public aliases, keeping the consumer import independent of the internal split.
- `Sources/SourceSymbols/Swift`, `Sources/SourceSymbols/Ruby`,
  `Sources/SourceSymbols/Kotlin` and `Sources/SourceSymbols/TypeScript` own their grammar
  interpretation, qualification, callable spellings, scope rules, trivia rules,
  and error recovery. Ruby also associates delayed heredoc bodies with their owners.
- `Sources/SourceSymbols/TreeSitter` shares only parser/tree ownership and borrowed
  node access. All backends use the same runtime without exposing backend handles.
- Grammar C targets come from version-pinned SwiftPM dependencies. Ruby, Kotlin,
  and TypeScript/TSX use upstream packages; Swift uses our source-only
  `tree-sitter-swift-spm` package. Generated code stays in those packages, separate
  from handwritten adapters. See [grammar dependencies](GRAMMARS.md).

The core cannot depend on a language adapter: the adapter target depends on the
core. All extraction stays synchronous, Sendable, and in memory. No parser handle
can outlive the extraction call or appear in a result. File loading, UI, URLs,
editors, Git, and project-wide semantic resolution remain consumer responsibilities.

Shared Tree-sitter mechanics do not interpret node kinds, trivia, or recovery.
These differ by language: Ruby's extra nodes can be executable heredoc bodies,
while Swift's extra-node policy excludes trivia. Language policy stays in adapters.

## Shared metadata and language policy

The core stores backend-provided lookup spellings and compares them exactly. It
does not impose a separator on qualified names or generate Swift-style parameter
lists. Named lexical scopes are retained separately from those spellings; they do
not establish a project-wide semantic identity.

Callable parameters distinguish local names, external labels, passing styles,
optional annotations, explicit optional-parameter markers, and default presence. An absent annotation is represented
by nil rather than an empty string or fabricated type. Exact structured-signature
matching compares every represented field. It performs no language-specific
overload resolution. Name-only and annotation-only queries intentionally preserve
all candidates satisfying the supplied filters.

Optional declaration headers are source ranges, not display strings or matching
keys. The core validates snapshot ownership and nesting with identifier/full ranges;
backends decide which syntax forms a reliable contiguous header and when it is
unavailable. Consumer formatting and body-boundary interpretation never enter the
shared matcher. New backends must document and test their header conventions.

The core tests construct untyped positional, keyword, rest, and block parameter
metadata and arbitrary lookup spellings without invoking a parser. Those tests
validate representation and matching; the Ruby, Kotlin, and TypeScript/TSX integration corpora separately
validate extraction. The API remains open to breaking changes as another backend establishes
additional requirements; it does not claim an exhaustive model of every language.

## Adding a language

1. Add a `SourceLanguage` case alongside a real `DeclarationExtractor` implementation
   in its own directory under `Sources/SourceSymbols`. Keep the single library product.
2. Pin and document any new runtime or grammar, preserving generated-source and
   license provenance. Keep its backend handles private to each extraction call.
3. Specify declaration categories, lexical scope rules, qualification, and callable
   lookup spellings from the language syntax. Preserve every syntactic candidate and parse
   diagnostic; do not infer runtime redefinition or dispatch behavior.
4. Add independently authored fixtures with exact byte ranges. Reuse
   `Tests/SourceSymbolsTests/Support/BackendContract.swift` for snapshot ownership,
   UTF-8/UTF-16 validity, declaration and diagnostic order, and missing/unique/
   ambiguous matching. Keep language-specific syntax and signature expectations
   in its own tests. Include malformed input, Unicode, CRLF, and concurrent calls.
5. Run `make check`, record the coverage and limitations, and validate the actual
   compiler/platform combinations before claiming support.
