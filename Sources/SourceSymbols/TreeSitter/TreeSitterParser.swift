import TreeSitter

public enum TreeSitterExtractionError: Error, Sendable {
    case sourceTooLarge
    case parserUnavailable
    case incompatibleLanguage
    case parseFailed
}

/// Owns the parser and tree for the duration of a synchronous extraction.
enum TreeSitterParser {
    static func extract(from snapshot: SourceSnapshot, language: OpaquePointer?,
                        using extract: (SyntaxNode) throws -> ExtractionResult) throws -> ExtractionResult
    {
        guard snapshot.text.utf8.count <= Int(UInt32.max) else { throw TreeSitterExtractionError.sourceTooLarge }
        guard let parser = ts_parser_new() else { throw TreeSitterExtractionError.parserUnavailable }
        defer { ts_parser_delete(parser) }
        guard ts_parser_set_language(parser, language) else {
            throw TreeSitterExtractionError.incompatibleLanguage
        }
        // Pass the actual UTF-8 length, including embedded NULs, rather than strlen.
        let tree = snapshot.text.withCString {
            ts_parser_parse_string(parser, nil, $0, UInt32(snapshot.text.utf8.count))
        }
        guard let tree else { throw TreeSitterExtractionError.parseFailed }
        defer { ts_tree_delete(tree) }
        return try extract(SyntaxNode(raw: ts_tree_root_node(tree)))
    }
}
