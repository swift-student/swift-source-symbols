import TreeSitter

/// Internal, borrowed view. Every use is confined to the lifetime of the owning tree.
struct SyntaxNode {
    let raw: TSNode
    var kind: String {
        String(cString: ts_node_type(raw))
    }

    var start: Int {
        Int(ts_node_start_byte(raw))
    }

    var end: Int {
        Int(ts_node_end_byte(raw))
    }

    var offsets: Range<Int> {
        start ..< end
    }

    var isMissing: Bool {
        ts_node_is_missing(raw)
    }

    var hasError: Bool {
        ts_node_has_error(raw)
    }

    var isExtra: Bool {
        ts_node_is_extra(raw)
    }

    var isError: Bool {
        ts_node_is_error(raw)
    }

    var children: [SyntaxNode] {
        (0 ..< ts_node_child_count(raw)).map { SyntaxNode(raw: ts_node_child(raw, $0)) }
    }

    func field(_ name: String) -> SyntaxNode? {
        let child = name.withCString { ts_node_child_by_field_name(raw, $0, UInt32(name.utf8.count)) }
        return ts_node_is_null(child) ? nil : SyntaxNode(raw: child)
    }

    func children(inField name: String) -> [SyntaxNode] {
        (0 ..< ts_node_child_count(raw)).compactMap { index in
            guard let field = ts_node_field_name_for_child(raw, index),
                  String(cString: field) == name else { return nil }
            return SyntaxNode(raw: ts_node_child(raw, index))
        }
    }
}
