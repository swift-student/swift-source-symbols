# Tree-sitter Kotlin 1.1.0

Unmodified files from the upstream Git tag
https://github.com/tree-sitter-grammars/tree-sitter-kotlin/releases/tag/v1.1.0
(commit `77dd60ea0a9003ce062c9728a513ffe1aaff8c82`).

`src/parser.c` is generated upstream (language ABI 14); it is committed in the tag.
`src/scanner.c`, `src/tree_sitter/*.h`, and `LICENSE` are copied verbatim.
`include/kotlin.h` is copied from `bindings/c/tree-sitter-kotlin.h`.
See SHA256SUMS for the exact shipped files and LICENSE for the upstream MIT license.

Consumer builds require neither Kotlin/JVM nor a parser generator. The shared
Tree-sitter runtime remains pinned to 0.25.10 in Package.swift and Package.resolved.
No queries or upstream package build scripts are used.

To update, check out an upstream release tag, record its commit, copy these files,
regenerate SHA256SUMS, and run the Kotlin fixture corpus and `make check`.
Do not hand-edit generated or vendored code.
