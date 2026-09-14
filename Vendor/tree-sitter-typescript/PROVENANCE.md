# Tree-sitter TypeScript / TSX 0.23.2

Unmodified files from the upstream Git tag
https://github.com/tree-sitter/tree-sitter-typescript/releases/tag/v0.23.2
(commit `f975a621f4e7f532fe322e13c4f79495e0a7b2e7`).

`typescript/src/parser.c` and `tsx/src/parser.c` are generated upstream (language
ABI 14) and committed in the tag. Both dialects' `src/scanner.c`,
`src/tree_sitter/*.h`, the shared `common/scanner.h`, and the MIT `LICENSE` are
copied verbatim. `include/typescript.h` and `include/tsx.h` are copied from
`bindings/c/tree-sitter-typescript.h` and `bindings/c/tree-sitter-tsx.h`.
SHA256SUMS records every shipped upstream file, using its destination path.

The parsers are compiled in one C target with distinct language entry points.
Consumers need neither Node.js, TypeScript, nor a parser generator. The shared
Tree-sitter runtime remains pinned to 0.25.10 in Package.swift and Package.resolved.
No upstream queries or package build scripts are used.

To update, check out an upstream release tag, record its commit, copy these files,
regenerate SHA256SUMS, and run the TypeScript/TSX corpus and `make check`.
Do not hand-edit generated or vendored code.
