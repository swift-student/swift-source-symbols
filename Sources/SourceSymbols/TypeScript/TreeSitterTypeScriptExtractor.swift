import TreeSitterTypeScriptGrammar

/// Extracts per-file TypeScript or TSX syntax with grammar 0.23.2 and runtime 0.25.10.
/// Lookup paths describe lexical syntax, without module resolution or type checking.
public struct TreeSitterTypeScriptExtractor: DeclarationExtractor {
    public init() {}

    public func extract(from snapshot: SourceSnapshot) throws -> ExtractionResult {
        let language: OpaquePointer?
        switch snapshot.language {
        case .typescript: language = tree_sitter_typescript()
        case .tsx: language = tree_sitter_tsx()
        default: throw ExtractionError.unsupportedLanguage(snapshot.language)
        }
        return try TreeSitterParser.extract(from: snapshot, language: language) { root in
            var extraction = TypeScriptSyntaxExtraction(snapshot: snapshot)
            return try extraction.extract(root: root)
        }
    }
}

struct TypeScriptSyntaxExtraction {
    enum Members { case none, classBody, objectBody }

    struct Context {
        var scopes: [String] = []
        var members: Members = .none

        func nested(_ name: String) -> Context {
            Context(scopes: scopes + [name])
        }
    }

    struct Work {
        let node: SyntaxNode
        var context: Context
        var rangeOwner: SyntaxNode?
    }

    let snapshot: SourceSnapshot
    let bytes: [UInt8]
    var declarations: [Declaration] = []

    init(snapshot: SourceSnapshot) {
        self.snapshot = snapshot
        bytes = Array(snapshot.text.utf8)
    }

    mutating func extract(root: SyntaxNode) throws -> ExtractionResult {
        // Diagnostics cover the entire tree, including syntax omitted from declaration traversal.
        let diagnostics = diagnostics(in: root)
        var stack = [Work(node: root, context: Context())]
        while let work = stack.popLast() {
            try stack.append(contentsOf: visit(work).reversed())
        }
        return try ExtractionResult(snapshot: snapshot, declarations: declarations, diagnostics: diagnostics)
    }

    private mutating func visit(_ work: Work) throws -> [Work] {
        let node = work.node
        let context = work.context
        let owner = work.rangeOwner ?? node
        switch node.kind {
        case "export_statement":
            guard let child = node.field("declaration") ?? node.field("value") else { return [] }
            return [Work(node: child, context: context, rangeOwner: owner)]
        case "ambient_declaration":
            return node.children.map {
                Work(node: $0, context: context, rangeOwner: $0.kind == "statement_block" ? nil : owner)
            }
        case "class_declaration", "abstract_class_declaration", "class", "interface_declaration",
             "enum_declaration", "internal_module", "module", "type_alias_declaration":
            return try typeWork(work)
        case "function_declaration", "generator_function_declaration", "function_signature",
             "function_expression", "generator_function", "arrow_function":
            return try callableWork(work, kind: .function)
        case "method_definition", "method_signature", "abstract_method_signature":
            guard context.members != .none else { return children(node, context: context) }
            let isAccessor = node.children.contains { ["get", "set"].contains($0.kind) }
            let isConstructor = context.members == .classBody && node.field("name").map(text) == "constructor"
                && !node.children.contains { $0.kind == "static" }
            return try callableWork(work, kind: isAccessor ? .property : isConstructor ? .initializer : .method)
        case "lexical_declaration", "variable_declaration":
            return try bindingWork(work)
        case "public_field_definition", "property_signature", "pair", "shorthand_property_identifier":
            guard context.members != .none else { return children(node, context: context) }
            return try propertyWork(work)
        case "class_body":
            return children(node, context: Context(scopes: context.scopes, members: .classBody))
        case "interface_body", "object":
            return children(node, context: Context(scopes: context.scopes, members: .objectBody))
        case "enum_body":
            return try enumWork(work)
        case "for_in_statement":
            if let keyword = node.field("kind"), let pattern = node.field("left") {
                let offsets = keyword.start ..< (node.field("value")?.end ?? pattern.end)
                for identifier in bindings(pattern) {
                    try append(identifier, owner: node, kind: .variable, context: context,
                               header: healthy(pattern) ? snapshot.range(offsets) : nil, fullOffsets: offsets)
                }
            }
            return children(node, context: Context(scopes: context.scopes))
        // Type-level names and parameter bindings are metadata, not independently navigable declarations.
        case "type_annotation", "type_parameters", "type_arguments", "object_type", "function_type",
             "constructor_type", "import_statement", "import_alias", "import_require_clause":
            return []
        default:
            return children(node, context: Context(scopes: context.scopes))
        }
    }

    private mutating func typeWork(_ work: Work) throws -> [Work] {
        let node = work.node
        let owner = work.rangeOwner ?? node
        var nested = Context(scopes: work.context.scopes)
        if let path = node.field("name"), healthy(path) {
            let identifier = path.kind == "nested_identifier" ? path.field("property") : path
            let name = path.kind == "nested_identifier" ? pathSpelling(path) : text(path)
            let kind: Declaration.Kind = switch node.kind {
            case "type_alias_declaration": .typeAlias
            case "module", "internal_module": .extensionScope
            default: .type
            }
            if let identifier, isName(identifier) {
                try append(identifier, owner: owner, kind: kind, context: work.context,
                           header: headerRange(node, owner: owner), lookupName: name)
                nested = work.context.nested(name)
            }
        }
        return node.children.flatMap { child -> [Work] in
            if same(child, node.field("body")) {
                return [Work(node: child, context: nested)]
            }
            if node.kind == "type_alias_declaration", same(child, node.field("value")), child.kind == "object_type" {
                return children(child, context: Context(scopes: nested.scopes, members: .objectBody))
            }
            return [Work(node: child, context: Context(scopes: work.context.scopes))]
        }
    }

    private mutating func callableWork(_ work: Work, kind: Declaration.Kind) throws -> [Work] {
        let node = work.node
        var nested = Context(scopes: work.context.scopes)
        if let identifier = node.field("name"), isName(identifier), healthy(identifier) {
            let header = headerRange(node, owner: work.rangeOwner ?? node)
            try append(identifier, owner: work.rangeOwner ?? node, kind: kind,
                       context: work.context, signature: header == nil ? nil : signature(node), header: header)
            nested = work.context.nested(text(identifier))
        }
        return node.children.map { child in
            let inCallable = same(child, node.field("body")) || same(child, node.field("parameters"))
            return Work(node: child, context: inCallable ? nested : Context(scopes: work.context.scopes))
        }
    }

    private mutating func bindingWork(_ work: Work) throws -> [Work] {
        let node = work.node
        let owner = work.rangeOwner ?? node
        let declarators = node.children.filter { $0.kind == "variable_declarator" }
        // All grouped bindings precede their initializer descendants, sharing the statement range.
        for declarator in declarators {
            guard let pattern = declarator.field("name") else { continue }
            for identifier in bindings(pattern) {
                let callable = pattern.kind == "identifier" ? callableValue(declarator.field("value")) : nil
                try append(identifier, owner: owner, kind: .variable, context: work.context,
                           signature: callable.flatMap(signature), header: headerRange(node, owner: owner))
            }
        }
        return declarators.flatMap { declarator in
            let pattern = declarator.field("name")
            let nested: Context = if let pattern, pattern.kind == "identifier", healthy(pattern) {
                work.context.nested(text(pattern))
            } else {
                Context(scopes: work.context.scopes)
            }
            return children(declarator, context: nested)
        }
    }

    private mutating func propertyWork(_ work: Work) throws -> [Work] {
        let node = work.node
        let identifier = node.field("name") ?? node.field("key")
            ?? (node.kind == "shorthand_property_identifier" ? node : nil)
        guard let identifier, isName(identifier), healthy(identifier) else {
            return children(node, context: Context(scopes: work.context.scopes))
        }
        let callable = callableValue(node.field("value"))
        try append(identifier, owner: node, kind: .property, context: work.context,
                   signature: callable.flatMap(signature), header: headerRange(node, owner: node))
        return children(node, context: work.context.nested(text(identifier)))
    }

    private mutating func enumWork(_ work: Work) throws -> [Work] {
        var result: [Work] = []
        let names = work.node.children(inField: "name")
        for child in work.node.children {
            let identifier = child.kind == "enum_assignment" ? child.field("name")
                : names.contains(where: { same(child, $0) }) ? child : nil
            var context = work.context
            if let identifier, isName(identifier), healthy(identifier) {
                try append(identifier, owner: child, kind: .enumCase, context: context,
                           header: headerRange(child, owner: child))
                context = context.nested(text(identifier))
            }
            result.append(Work(node: child, context: context))
        }
        return result
    }

    private mutating func append(_ identifier: SyntaxNode, owner: SyntaxNode,
                                 kind: Declaration.Kind, context: Context, signature: CallableSignature? = nil,
                                 header: SourceRange?, lookupName: String? = nil, fullOffsets: Range<Int>? = nil) throws
    {
        guard healthy(identifier), let identifierRange = snapshot.range(identifier.offsets),
              let start = boundary(owner, fromEnd: false), let end = boundary(owner, fromEnd: true),
              let full = snapshot.range(fullOffsets ?? start ..< end) else { return }
        let name = text(identifier)
        try declarations.append(Declaration(
            name: name,
            qualifiedName: (context.scopes + [lookupName ?? name]).joined(separator: "."),
            kind: kind,
            signature: signature,
            enclosingScopes: context.scopes,
            identifierRange: identifierRange,
            declarationRange: full,
            headerRange: header
        ))
    }

    private func children(_ node: SyntaxNode, context: Context) -> [Work] {
        node.children.map { Work(node: $0, context: context) }
    }

    private func bindings(_ node: SyntaxNode) -> [SyntaxNode] {
        switch node.kind {
        case "identifier", "shorthand_property_identifier_pattern": healthy(node) ? [node] : []
        case "pair_pattern": node.field("value").map(bindings) ?? []
        case "assignment_pattern", "object_assignment_pattern": node.field("left").map(bindings) ?? []
        case "array_pattern", "object_pattern", "rest_pattern": node.children.flatMap(bindings)
        default: []
        }
    }

    private func pathSpelling(_ node: SyntaxNode) -> String {
        if node.kind == "comment" {
            return ""
        }
        return node.children.isEmpty ? text(node) : node.children.map(pathSpelling).joined()
    }

    func isName(_ node: SyntaxNode) -> Bool {
        ["identifier", "type_identifier", "property_identifier", "private_property_identifier", "string", "number",
         "shorthand_property_identifier", "shorthand_property_identifier_pattern"].contains(node.kind)
    }

    func healthy(_ node: SyntaxNode) -> Bool {
        !node.hasError && !node.isMissing && node.end > node.start
    }

    func same(_ node: SyntaxNode, _ other: SyntaxNode?) -> Bool {
        node.kind == other?.kind && node.offsets == other?.offsets
    }

    func text(_ node: SyntaxNode) -> String {
        String(decoding: bytes[node.offsets], as: UTF8.self)
    }
}
