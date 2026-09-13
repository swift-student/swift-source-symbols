import TreeSitter
import TreeSitterSwiftGrammar

public enum TreeSitterExtractionError: Error, Sendable {
    case sourceTooLarge
    case parserUnavailable
    case incompatibleLanguage
    case parseFailed
}

/// Extracts per-file Swift syntax using Tree-sitter Swift 0.7.3 and runtime 0.25.10.
/// Each call owns its parser and tree. Results contain no backend handles.
public struct TreeSitterSwiftExtractor: DeclarationExtractor {
    public init() {}

    public func extract(from snapshot: SourceSnapshot) throws -> ExtractionResult {
        guard snapshot.language == .swift else { throw ExtractionError.unsupportedLanguage(snapshot.language) }
        guard snapshot.text.utf8.count <= Int(UInt32.max) else { throw TreeSitterExtractionError.sourceTooLarge }
        guard let parser = ts_parser_new() else { throw TreeSitterExtractionError.parserUnavailable }
        defer { ts_parser_delete(parser) }
        guard ts_parser_set_language(parser, tree_sitter_swift()) else {
            throw TreeSitterExtractionError.incompatibleLanguage
        }
        // Pass the actual UTF-8 length, including embedded NULs, rather than strlen.
        let tree = snapshot.text.withCString {
            ts_parser_parse_string(parser, nil, $0, UInt32(snapshot.text.utf8.count))
        }
        guard let tree else { throw TreeSitterExtractionError.parseFailed }
        defer { ts_tree_delete(tree) }
        var extraction = SwiftSyntaxExtraction(snapshot: snapshot)
        return try extraction.extract(root: SyntaxNode(raw: ts_tree_root_node(tree)))
    }
}

/// Private, borrowed view. Every use is confined to the lifetime of the owning tree.
private struct SyntaxNode {
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

    var isError: Bool {
        ts_node_is_error(raw)
    }

    var isTrivia: Bool {
        ts_node_is_extra(raw) && !isError || kind == "comment" || kind == "multiline_comment"
    }

    var children: [SyntaxNode] {
        (0 ..< ts_node_child_count(raw)).map { SyntaxNode(raw: ts_node_child(raw, $0)) }
    }

    var syntaxChildren: [SyntaxNode] {
        children.filter { !$0.isTrivia && !$0.isMissing && $0.end > $0.start }
    }

    func syntaxBoundary(fromEnd: Bool) -> Int? {
        var stack = [self]
        while let node = stack.popLast() {
            guard !node.isTrivia, !node.isMissing, node.end > node.start else { continue }
            // Keep healthy spans intact, including tokens hidden by the public node API.
            // Recovered subtrees can extend through trivia to a missing token at EOF.
            let children = node.children
            if !node.hasError || children.isEmpty {
                return fromEnd ? node.end : node.start
            }
            stack.append(contentsOf: fromEnd ? children : children.reversed())
        }
        return nil
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

private struct SwiftSyntaxExtraction {
    enum Context { case file, type, local }
    struct Work {
        let node: SyntaxNode
        let scopes: [String]
        let context: Context
    }

    let snapshot: SourceSnapshot
    private let bytes: [UInt8]
    private var declarations: [Declaration] = []
    private var diagnostics: [ParseDiagnostic] = []

    init(snapshot: SourceSnapshot) {
        self.snapshot = snapshot
        bytes = Array(snapshot.text.utf8)
    }

    mutating func extract(root: SyntaxNode) throws -> ExtractionResult {
        var stack = [Work(node: root, scopes: [], context: .file)]
        while let work = stack.popLast() {
            let node = work.node
            let nodeChildren = node.children
            if node.isError || node.isMissing {
                diagnostics.append(ParseDiagnostic(
                    severity: .error,
                    message: node.isMissing ? "Tree-sitter: missing \(node.kind)" : "Tree-sitter: unrecognized syntax",
                    range: snapshot.range(node.offsets)
                ))
            } else if node.hasError, !nodeChildren.contains(where: \.hasError) {
                // Some grammar tokens are hidden by the public node API. Their nearest
                // visible ancestor hasError even though no ERROR/MISSING child is exposed.
                diagnostics.append(ParseDiagnostic(severity: .error,
                                                   message: "Tree-sitter: recovered syntax in \(node.kind)",
                                                   range: snapshot.range(node.offsets)))
            }
            let found = try extractDeclarations(node, scopes: work.scopes, context: work.context)
            declarations.append(contentsOf: found)
            var scopes = work.scopes
            var context = work.context
            if let declaration = found.first {
                switch declaration.kind {
                case .type, .extensionScope:
                    scopes.append(declaration.name)
                    context = .type
                case .function, .method, .initializer, .deinitializer, .subscriptDeclaration:
                    scopes.append(declaration.name)
                    context = .local
                case .property, .variable:
                    // A property's initializer/accessors are not the enclosing type's member scope.
                    context = .local
                default: break
                }
            }
            if node.kind == "lambda_literal" {
                context = .local
            }
            var children: [Work] = []
            var bindingScope: [String] = []
            for child in nodeChildren {
                if node.kind == "property_declaration" || node.kind == "protocol_property_declaration",
                   child.kind == "pattern"
                {
                    // Each comma-separated initializer belongs to its own binding. A tuple
                    // binding has no single name with which to qualify its shared initializer.
                    bindingScope = []
                    if let nameNode = singleBindingName(child),
                       let binding = found.first(where: { $0.identifierRange.utf8Offsets == nameNode.offsets })
                    {
                        bindingScope = [binding.name]
                    }
                }
                children.append(Work(node: child, scopes: scopes + bindingScope, context: context))
            }
            stack.append(contentsOf: children.reversed())
        }
        if root.hasError, diagnostics.isEmpty {
            diagnostics.append(ParseDiagnostic(severity: .error, message: "Tree-sitter: recovered parse error",
                                               range: snapshot.range(root.offsets)))
        }
        return try ExtractionResult(snapshot: snapshot, declarations: declarations, diagnostics: diagnostics)
    }

    private func extractDeclarations(_ node: SyntaxNode, scopes: [String], context: Context) throws -> [Declaration] {
        let kind: Declaration.Kind
        var names: [SyntaxNode]
        var signature: CallableSignature?
        switch node.kind {
        case "class_declaration", "protocol_declaration":
            kind = node.field("declaration_kind").map(text) == "extension" ? .extensionScope : .type
            names = node.field("name").map { [$0] } ?? []
        case "function_declaration", "protocol_function_declaration", "init_declaration", "subscript_declaration",
             "deinit_declaration":
            switch node.kind {
            case "init_declaration": kind = .initializer
            case "subscript_declaration": kind = .subscriptDeclaration
            case "deinit_declaration": kind = .deinitializer
            default: kind = context == .type ? .method : .function
            }
            let name = node.kind == "subscript_declaration" || node.kind == "deinit_declaration"
                ? node.children.first { $0.kind == "subscript" || $0.kind == "deinit" }
                : node.field("name")
            names = name.map { [$0] } ?? []
            signature = callableSignature(node)
        case "property_declaration", "protocol_property_declaration":
            kind = context == .type ? .property : .variable
            names = node.children.filter { $0.kind == "pattern" }.flatMap(bindingNames)
        case "typealias_declaration", "associatedtype_declaration":
            kind = node.kind == "typealias_declaration" ? .typeAlias : .associatedType
            names = node.field("name").map { [$0] } ?? []
        case "enum_entry":
            kind = .enumCase
            names = node.children(inField: "name")
        default: return []
        }
        let children = node.syntaxChildren
        guard let start = children.lazy.compactMap({ $0.syntaxBoundary(fromEnd: false) }).first,
              let end = children.reversed().lazy.compactMap({ $0.syntaxBoundary(fromEnd: true) }).first,
              let fullRange = snapshot.range(start ..< end) else { return [] }
        return try names.compactMap { nameNode in
            guard !nameNode.isMissing, !nameNode.hasError, nameNode.end > nameNode.start,
                  let identifierRange = snapshot.range(nameNode.offsets) else { return nil }
            let name = kind == .extensionScope ? extensionName(nameNode) : unescape(text(nameNode))
            guard !name.isEmpty else { return nil }
            return try Declaration(name: name, qualifiedName: (scopes + [name]).joined(separator: "."),
                                   kind: kind, signature: signature, enclosingScopes: scopes,
                                   identifierRange: identifierRange, declarationRange: fullRange)
        }
    }

    private func bindingNames(_ pattern: SyntaxNode) -> [SyntaxNode] {
        if let name = singleBindingName(pattern) {
            return [name]
        }
        // Tuple labels are direct identifiers; only nested patterns introduce bindings.
        return pattern.children.filter { $0.kind == "pattern" }.flatMap(bindingNames)
    }

    private func singleBindingName(_ pattern: SyntaxNode) -> SyntaxNode? {
        if let bound = pattern.field("bound_identifier") {
            return bound
        }
        let children = pattern.syntaxChildren
        if children.count == 1, children[0].kind == "simple_identifier" {
            return children[0]
        }
        // Parenthesizing one binding does not turn it into a tuple pattern.
        if children.count == 3, children[0].kind == "(", children[1].kind == "pattern", children[2].kind == ")" {
            return singleBindingName(children[1])
        }
        return nil
    }

    private func callableSignature(_ node: SyntaxNode) -> CallableSignature? {
        let header = node.children.prefix { $0.kind != "function_body" && $0.kind != "computed_property" }
        guard !header.contains(where: { $0.hasError || $0.isMissing }) else { return nil }
        if node.kind == "deinit_declaration" {
            return CallableSignature(parameters: [])
        }
        // A damaged parameter list must not be represented as a clean zero-argument signature.
        guard header.contains(where: { $0.kind == "(" }), header.contains(where: { $0.kind == ")" }) else { return nil }
        let parameterNodes = header.filter { $0.kind == "parameter" }
        var parameters: [CallableSignature.Parameter] = []
        for parameter in parameterNodes {
            let children = parameter.syntaxChildren
            guard let colon = children.firstIndex(where: { $0.kind == ":" }),
                  let localName = children[..<colon].last(where: { $0.kind == "simple_identifier" }),
                  let typeStart = children.dropFirst(colon + 1).first,
                  let typeEnd = children.last else { return nil }
            let externalName = parameter.field("external_name")
            // Operators and subscripts do not use their local parameter names as argument labels.
            let isOperator = (node.kind == "function_declaration" || node.kind == "protocol_function_declaration")
                && node.field("name")?.kind != "simple_identifier"
            let defaultsToUnlabeled = isOperator || node.kind == "subscript_declaration"
            let label = externalName.map { unescape(text($0)) }
                ?? (defaultsToUnlabeled ? "_" : unescape(text(localName)))
            parameters.append(.init(argumentLabel: label, typeSyntax: text(typeStart.start ..< typeEnd.end)))
        }
        var returnType: String?
        if let arrow = header.firstIndex(where: { $0.kind == "->" }) {
            // Return annotations and an implicitly unwrapped suffix can be separate nodes.
            let type = header.suffix(from: header.index(after: arrow))
                .prefix { $0.kind != "type_constraints" }.filter { !$0.isTrivia }
            if let first = type.first, let last = type.last {
                returnType = text(first.start ..< last.end)
            }
        }
        return CallableSignature(
            parameters: parameters,
            genericParameters: header.first(where: { $0.kind == "type_parameters" }).map(text),
            effects: header.filter { ["async", "throws", "throws_clause"].contains($0.kind) }.map(text),
            returnType: returnType,
            genericConstraints: header.first(where: { $0.kind == "type_constraints" }).map(text)
        )
    }

    private func extensionName(_ node: SyntaxNode) -> String {
        // Token-based qualification removes trivia and identifier escaping, not generic syntax.
        let children = node.children.filter { !$0.isTrivia }
        if children.isEmpty {
            return unescape(text(node))
        }
        return children.map(extensionName).joined()
    }

    private func text(_ node: SyntaxNode) -> String {
        text(node.offsets)
    }

    private func text(_ offsets: Range<Int>) -> String {
        String(decoding: bytes[offsets], as: UTF8.self)
    }

    private func unescape(_ name: String) -> String {
        name.hasPrefix("`") && name.hasSuffix("`") ? String(name.dropFirst().dropLast()) : name
    }
}
