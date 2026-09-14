# Kotlin fixtures

These fixtures are independently authored for the Kotlin adapter. JSON expectations
specify declarations, kinds, outer-to-inner lexical scopes, exact half-open UTF-8
identifier/full ranges, qualified names, and diagnostic ranges in traversal order.
Expected byte offsets were calculated from authored source spans, not generated
from extractor output. Swift Testing separately specifies signatures, source-backed
headers, missing/unique/ambiguous matches, positions, and concurrent extraction.

- `declarations`: packages, classes/interfaces, primary property parameters,
  secondary constructors, init blocks, overloads, properties/accessors, companion
  and named objects, enum entries, aliases, and destructuring.
- `parameters`: defaults, varargs, named arguments, function/generic/nullable types,
  constraints, suspend, extension receivers, and constructor signatures.
- `scopes`: local classes, anonymous blocks/lambdas/objects, initializer/accessor
  scopes, named companions, and member extension functions.
- `syntax`: annotation/value classes, sealed/fun interfaces, enum entry bodies,
  operator/infix functions, raw strings, nested comments, declarations in default
  lambdas, and repeated definitions.
- `trivia`: exact headers with annotations, nested braces and type comments;
  stored/delegated/computed properties and aliases.
- `unicode-lf` / `unicode-crlf`: identical logical text with precomposed and combining
  Unicode, backticks, CJK, and emoji. Preserve their exact bytes and line endings.
- `recovery`, `damaged-default`, `incomplete`: body/header errors, missing tokens,
  preserved candidates, and lost ancestor scopes under grammar recovery.
- `compact`: pinned-grammar false positive for a same-line class member separator.

The shared BackendContract helper validates snapshot ownership and UTF-8/UTF-16
ranges for both declarations and diagnostics. See docs/KOTLIN_BACKEND.md for the
coverage boundary; fixtures do not establish compiler or platform compatibility.
