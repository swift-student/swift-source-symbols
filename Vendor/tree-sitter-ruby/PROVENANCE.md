# Tree-sitter Ruby 0.23.1

Unmodified files from the upstream Git tag
https://github.com/tree-sitter/tree-sitter-ruby/releases/tag/v0.23.1
(commit `71bd32fb7607035768799732addba884a37a6210`).

`src/parser.c` is generated upstream (language ABI 14); it is committed in the tag.
`src/scanner.c`, `src/tree_sitter/*.h`, and `LICENSE` are copied verbatim.
`include/ruby.h` is copied from `bindings/c/tree-sitter-ruby.h`.
See SHA256SUMS for the exact shipped files and LICENSE for the upstream MIT license.

Consumer builds require neither a Ruby interpreter nor a parser generator. The
Tree-sitter runtime is separately pinned to 0.25.10 in Package.swift and
Package.resolved. No Tags queries or upstream package build scripts are used.

To update, check out an upstream release tag, record its commit, copy these files,
regenerate SHA256SUMS, and run the Ruby fixture corpus and `make check`.
Do not hand-edit generated or vendored code.
