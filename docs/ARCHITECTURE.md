# Architecture

SourceSymbols is one library product for projects containing multiple languages.
Consumers use `import SourceSymbols`; the product bundles every implemented backend.
There are no per-language product choices or external backend registration system.
Swift is the only implemented language. Ruby extraction belongs in the next PR.

## Internal boundaries

- `Sources/SourceSymbolsCore` contains snapshots, ranges, declarations, callable
  metadata, diagnostics, the extractor protocol, and exact matching. This target
  depends only on Foundation and has no parser dependency.
- `Sources/SourceSymbols/Exports.swift` exposes the shared types through explicit
  public aliases, keeping the consumer import independent of the internal split.
- `Sources/SourceSymbols/Swift` implements Swift extraction and owns its grammar
  interpretation, qualification, callable spellings, scope rules, trivia rules,
  and error recovery. A later `Ruby` directory can implement the same protocol.
- `Vendor/tree-sitter-swift` is a separate C target with pinned provenance.
  Vendored or generated code never mixes with handwritten Swift.

The core cannot depend on a language adapter: the adapter target depends on the
core. All extraction stays synchronous, Sendable, and in memory. No parser handle
can outlive the extraction call or appear in a result. File loading, UI, URLs,
editors, Git, and project-wide semantic resolution remain consumer responsibilities.

Tree-sitter ownership and borrowed-node access are candidates for internal reuse
when a second backend exists. Do not generalize Swift node names, trivia treatment,
recovery assumptions, or scope traversal into a universal parser. The first Ruby
implementation should establish which mechanics actually have identical contracts.

## Shared metadata and language policy

The core stores backend-provided lookup spellings and compares them exactly. It
does not impose a separator on qualified names or generate Swift-style parameter
lists. Named lexical scopes are retained separately from those spellings; they do
not establish a project-wide semantic identity.

Callable parameters distinguish local names, external labels, passing styles,
optional annotations, and default presence. An absent annotation is represented
by nil rather than an empty string or fabricated type. Exact structured-signature
matching compares every represented field. It performs no language-specific
overload resolution. Name-only and annotation-only queries intentionally preserve
all candidates satisfying the supplied filters.

The core tests construct untyped positional, keyword, rest, and block parameter
metadata and arbitrary lookup spellings without invoking a parser. Those tests
validate representation and matching, not Ruby extraction support or completeness.
The API remains open to breaking changes as the next real backend establishes
additional requirements; it does not claim an exhaustive model of every language.

## Adding Ruby

1. Add `.ruby` to `SourceLanguage` alongside a real `DeclarationExtractor`
   implementation under `Sources/SourceSymbols/Ruby`. Keep the single library product.
2. Pin and document any new runtime or grammar, preserving generated-source and
   license provenance. Keep its backend handles private to each extraction call.
3. Specify declaration categories, lexical scope rules, qualification, and callable
   lookup spellings from Ruby syntax. Preserve every syntactic candidate and parse
   diagnostic; do not infer runtime redefinition or dispatch behavior.
4. Add independently authored fixtures with exact byte ranges. Reuse
   `Tests/SourceSymbolsTests/Support/BackendContract.swift` for snapshot ownership,
   UTF-8/UTF-16 validity, declaration and diagnostic order, and missing/unique/
   ambiguous matching. Keep language-specific syntax and signature expectations
   in its own tests. Include malformed input, Unicode, CRLF, and concurrent calls.
5. Run `make check`, record the coverage and limitations, and validate the actual
   compiler/platform combinations before claiming support.
