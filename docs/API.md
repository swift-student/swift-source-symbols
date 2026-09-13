# Initial API decision

SourceSymbols operates on immutable in-memory SourceSnapshot values with an
explicit SourceLanguage. Each newly initialized snapshot has a unique identity;
copies retain that identity. SourceRange values can only be constructed by their
snapshot, and contain zero-based UTF-8 byte offsets with an exclusive upper bound.
Empty ranges, including EOF, are valid. Offsets must fall on Unicode scalar
boundaries; they may divide a composed grapheme. CRLF occupies two bytes. There
is no newline normalization. UTF-16 and line/column adapters are not implemented.
A range remains meaningful for the original snapshot, never for edited text.

Declaration contains a short name, qualified name, kind, optional exact signature,
outer-to-inner lexical scope names, identifier range, and full declaration range.
The identifier must be contained in the declaration. Extension scopes have their
own kind and must not be represented as newly introduced types. These are syntactic
per-file results, with no type checking or project-wide semantic resolution.

DeclarationExtractor is a Sendable synchronous throwing adapter protocol.
Unsupported languages throw ExtractionError.unsupportedLanguage; recovered parse
errors are ParseDiagnostic values alongside available declarations. Fatal backend
failures may throw backend-specific errors. ExtractionResult rejects ranges from
other snapshots. A successful match does not imply a clean parse; inspect diagnostics.
There is no bundled production extractor yet, so no language is currently supported
for general extraction. The example adapter accepts a single fixed fixture only.

DeclarationMatcher performs exact case-sensitive short or qualified name matching,
with an optional exact backend-defined signature filter. It returns missing,
unique, or every ambiguous candidate in input order. No fuzzy name matching,
signature normalization, deduplication, or arbitrary overload selection occurs.

The initial package declares Swift tools 6.0, Swift 6 language mode, and macOS 13
minimum deployment. It has been locally tested with Swift 6.4 on macOS; the minimum
compiler and deployment OS still need CI validation. iOS is a future consumer
requirement to evaluate, not tested support. No external parser dependency is
selected: issue #6 must evaluate SwiftParser/SwiftSyntax and Tree-sitter before
issue #5 finalizes packaging. UI, URLs, editor launching, file loading, Git snapshots,
and anchor relocation belong in consumer adapters.

The API may change before 1.0. No release or license grant is
made by this scaffold. The repository stays private pending an owner decision.
