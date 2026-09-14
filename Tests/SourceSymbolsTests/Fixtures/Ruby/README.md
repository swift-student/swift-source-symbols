# Ruby declaration corpus

These are original fixtures for the Ruby backend, not third-party application code.
JSON expectations are independently authored from source bytes and intended syntax,
never regenerated from extractor output. They specify declaration kinds, lexical
scopes, exact UTF-8 identifier/declaration offsets, qualified names, and diagnostics
in order. Swift Testing adds signature, matching, recovery, and concurrency checks
and reuses `Support/BackendContract.swift` for snapshot and range invariants.

- `declarations.rb`: modules, nested and reopened classes, constants, instance and
  singleton methods, singleton class bodies, aliases, operators/setters, nested defs.
- `parameters.rb`: positional, keyword, defaults, rest, keyword rest, block and
  anonymous parameters, plus forwarding/destructuring/keyword-rejection limits.
- `bindings.rb`: grouped/qualified constants and aliases, with negative reference,
  local/member assignment, global-alias, and metaprogramming examples.
- `syntax.rb`: qualified/absolute paths, receiver expressions, conditional branches,
  singleton nesting, visibility wrappers, comments, literals, heredocs, and `__END__`.
- `heredocs.rb`: delayed and multiple bodies, interpolation scope, default parameters,
  and an intervening statement on the opening line.
- `receiver-paths.rb`: receiver-rooted constant assignments, classes, and modules,
  preserving `self::` lexical scopes and qualification inside singleton bodies.
- `heredoc-recovery.rb`: intentionally malformed heredoc defaults and method bodies,
  including multiple delayed bodies belonging to different parts of one method.
- `adjacent-body-recovery.rb`: body errors immediately after closed parameter lists,
  with valid-body, damaged-parameter, and missing-parenthesis controls.
- `unicode-lf.rb` / `unicode-crlf.rb`: exact newline counterparts containing emoji,
  an accented module name, a decomposed method name, and a keyword parameter.
- `recovery.rb`, `missing.rb`, `incomplete.rb`: intentionally malformed inputs that
  preserve errors, zero-width missing tokens, header/body distinctions, and the
  pinned grammar's inability to reconstruct some unterminated declarations.

All eight valid fixtures passed `ruby -c` with Ruby 4.0.6 on 2026-09-14. The five
recovery/missing/incomplete fixtures intentionally contain invalid syntax.
The receiver-path and heredoc-recovery assertions also run with CRLF in-memory copies.
This checks syntax, not runtime behavior or whole-version conformance.
Preserve the original UTF-8 bytes and intentional CRLF. Do not format these files.
See [the backend contract](../../../../docs/RUBY_BACKEND.md) for coverage and limits.
