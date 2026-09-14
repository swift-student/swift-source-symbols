# Ruby backend contract

`TreeSitterRubyExtractor` is bundled in the `SourceSymbols` product and accepts
`.ruby` snapshots. It uses direct Tree-sitter node traversal, Ruby grammar 0.23.1
(language ABI 14), and the existing runtime 0.25.10. Each extraction owns its parser
and tree; only immutable model values leave the call. No Ruby interpreter, generator,
filesystem loading, or runtime evaluation is part of extraction.

The unmodified grammar, scanner, headers, and MIT license are pinned under
[Vendor/tree-sitter-ruby](../Vendor/tree-sitter-ruby/PROVENANCE.md), including the
upstream commit and file hashes. Shared Tree-sitter ownership and borrowed-node
access live under `Sources/SourceSymbols/TreeSitter`; language policy remains
in `Sources/SourceSymbols/Ruby`.

## Declarations and qualification

| Syntax | Kind | Lookup convention |
| --- | --- | --- |
| `module Shop; class Cart; end; end` | `type` for each | `Shop`, `Shop::Cart` |
| `class Shop::Cart; end` | `type` | Short name `Cart`, qualified `Shop::Cart` |
| `def add(item); end` in `Cart` | `method` | `Cart#add` |
| `def self.build; end` in `Cart` | `method` | `Cart.build` |
| `class << self; def build; end; end` in `Cart` | `extensionScope`, `method` | `Cart::<< self`, `Cart.build` |
| `VERSION = "1"` in `Cart` | `variable` | `Cart::VERSION` |
| `alias append add` in `Cart` | `method`, nil signature | `Cart#append` |

Every `def`, including top-level definitions and `initialize`, has kind `method`.
Top-level `def top; end` has qualified name `top`. Nested definitions add a lexical
component: `def top; def nested; end; end` produces `top::nested`. Operators, setters,
predicate/bang names, bare/parenthesized parameter lists, and endless methods retain
their source names. Ruby provides no `callableName`/`qualifiedCallableName` aliases.
Signature filters work with the same names; the core does not invent parameter lists.

Qualified names are syntactic lookup strings, not resolved Ruby identities. A
relative path is appended to the enclosing lexical namespace; `module Outer;
def Outer.helper; end; end` therefore produces `Outer::Outer.helper`. No attempt is
made to decide which runtime constant `Outer` refers to. A leading `::` explicitly
starts a root path and is retained, even inside another lexical module. Constant
path trivia is excluded from lookup spellings; the final constant token supplies
the short name and identifier range. A class body's scope component retains its
whole declared path, e.g. `["Outer", "Inner::Nested"]` for a member.

An explicit `self` receiver in a class/module body uses that body's syntactic
qualified name. `class << receiver` contributes a lexical `<< receiver` scope but
qualifies its ordinary methods with the receiver and `.`. Within that singleton
body, `self` is spelled `receiver.singleton_class`, preserving additional singleton
levels. Arbitrary receivers retain their expression spelling, parenthesized when
composite: `def (factory.call).build; end` is `(factory.call).build`. Inside a method,
`self` uses the method's lexical path plus `::self`, without guessing its runtime
receiver. Anonymous blocks and control flow add no named scope. Methods within
constant initializers retain the surrounding scope, without inferring a type from
`Class.new` or `Module.new` calls.

Constant paths use the same receiver rules. Inside `Host`, `self::VALUE` qualifies
as `Host::VALUE`, and `class self::Nested` introduces `Host::Nested` with methods
such as `Host::Nested#run`. Its lexical scope component remains `self::Nested`.
Inside `class << self`, a `self::` path uses the additional singleton level.
Other receiver roots retain their expression spelling: `class holder::Nested`
introduces `holder::Nested` at the top level and scopes its methods accordingly.

Reopened classes, branches, repeated definitions, and alias candidates remain
separate. Extraction never selects Ruby's eventual runtime definition. Constant
assignments, including grouped/destructured and operator assignments, are syntactic
binding candidates with kind `variable`; references, local/instance/class/global
variable assignments, and setter/index writes are omitted. Grouped constants share
the full assignment range. Static bare-name and simple-symbol aliases are included;
quoted/interpolated aliases and global-variable aliases are omitted.

## Signatures, ranges, and recovery

Signatures retain ordered local parameter names, keyword labels, passing channels,
and default presence. Ruby annotations, generic parameters, effects, return types,
and constraints are absent. Defaults are traversed as syntax, so nested calls,
arrays, hashes, lambdas, strings, regexes, and heredocs do not split parameters.
Anonymous `*`, `**`, and `&` have nil binding names. A known parameterless method has
an empty signature. Aliases and headers containing forwarding, destructuring, or
`**nil` have nil signatures: the current model cannot fully represent those headers.
These declarations remain available to name-only matching, while annotation and
signature filters cannot accidentally treat them as known zero-parameter methods.

Ranges are snapshot-bound, zero-based half-open UTF-8 offsets. Leading/trailing
comments and whitespace are excluded; interior bytes are preserved. Visibility
calls such as `private def` are not method syntax, so the method range starts at
`def`. Delayed heredoc bodies are associated with their opening statements, included
through the closing delimiter, and traversed in their owner's lexical context.
Contiguous ranges can consequently include an intervening statement on the opening
line. Results visit owners before descendants, then sibling statements; attached
heredoc interpolation declarations precede the owner's following siblings.

Error and missing-token diagnostics are preserved, including overlapping and
zero-width ranges. Damaged headers lose their signature. A sound header survives
an error in its body, including a body starting immediately after a closed
parameter list. Errors in delayed heredoc defaults invalidate the signature even
when their bodies follow the method's `end`; errors in body-owned heredocs preserve
a sound header. Only recognizable declaration nodes with healthy names are
extracted. The pinned grammar can collapse an unterminated class or method into
`ERROR`; tokens that no longer form a declaration node are not rebuilt by a second
parser. Surviving descendants then use the nearest recoverable lexical scope.
`incomplete.rb` permanently records this limit.

No methods are synthesized from `attr_reader`, `define_method`, `alias_method`,
`module_function`, `eval`, or other dynamic calls. No RBS/Sorbet annotation binding,
visibility analysis, inheritance lookup, ERB parsing, or complete Ruby-version
conformance is claimed. A clean parse does not imply complete extraction.

## Validation

The permanent [Ruby corpus](../Tests/SourceSymbolsTests/Fixtures/Ruby/README.md)
checks exact declaration/diagnostic byte ranges, qualification, all represented
parameter channels, redefinition ambiguity, aliases/constants, heredocs, Unicode
and CRLF, missing/erroneous syntax, embedded NULs, and concurrent calls. Existing
Swift fixtures validate that shared parser mechanics preserve Swift behavior.

Local validation uses Swift 6.4 in Swift 6 language mode on macOS 26.6.2 (arm64),
including `make check`. Valid Ruby fixtures were also accepted by Ruby 4.0.6's
syntax checker; this is not a claim of full Ruby 4 grammar support. The existing
Swift 6.0/6.2 CI matrix must validate these changes separately. macOS 13 runtime,
iOS, Linux, and other toolchains have not been validated for this backend.
