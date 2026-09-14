import TreeSitterSwiftGrammar

/// Extracts per-file Swift syntax using Tree-sitter Swift 0.7.3 and runtime 0.25.10.
/// Each call owns its parser and tree. Results contain no backend handles.
public struct TreeSitterSwiftExtractor: DeclarationExtractor {
    public init() {}

    public func extract(from snapshot: SourceSnapshot) throws -> ExtractionResult {
        guard snapshot.language == .swift else { throw ExtractionError.unsupportedLanguage(snapshot.language) }
        return try TreeSitterParser.extract(from: snapshot, language: tree_sitter_swift()) { root in
            var extraction = SwiftSyntaxExtraction(snapshot: snapshot)
            return try extraction.extract(root: root)
        }
    }
}

private extension SyntaxNode {
    var isTrivia: Bool {
        isExtra && !isError || kind == "comment" || kind == "multiline_comment"
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
}

private struct SwiftSyntaxExtraction {
    enum Context { case file, type, local }
    struct Work {
        let node: SyntaxNode
        let scopes: [String]
        let lookupScopes: [String]
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
        var stack = [Work(node: root, scopes: [], lookupScopes: [], context: .file)]
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
            let found = try extractDeclarations(node, scopes: work.scopes, lookupScopes: work.lookupScopes,
                                                context: work.context)
            declarations.append(contentsOf: found)
            var scopes = work.scopes
            var lookupScopes = work.lookupScopes
            var context = work.context
            if let declaration = found.first {
                switch declaration.kind {
                case .type, .extensionScope:
                    scopes.append(declaration.name)
                    lookupScopes.append(declaration.name)
                    context = .type
                case .function, .method, .initializer, .deinitializer, .subscriptDeclaration:
                    scopes.append(declaration.name)
                    lookupScopes.append(declaration.callableName ?? declaration.name)
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
                children.append(Work(node: child, scopes: scopes + bindingScope,
                                     lookupScopes: lookupScopes + bindingScope, context: context))
            }
            stack.append(contentsOf: children.reversed())
        }
        if root.hasError, diagnostics.isEmpty {
            diagnostics.append(ParseDiagnostic(severity: .error, message: "Tree-sitter: recovered parse error",
                                               range: snapshot.range(root.offsets)))
        }
        return try ExtractionResult(snapshot: snapshot, declarations: declarations, diagnostics: diagnostics)
    }

    private func extractDeclarations(_ node: SyntaxNode, scopes: [String], lookupScopes: [String],
                                     context: Context) throws -> [Declaration]
    {
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
        let header = headerRange(node)
        return try names.compactMap { nameNode in
            guard !nameNode.isMissing, !nameNode.hasError, nameNode.end > nameNode.start,
                  let identifierRange = snapshot.range(nameNode.offsets) else { return nil }
            let name = kind == .extensionScope ? extensionName(nameNode) : unescape(text(nameNode))
            guard !name.isEmpty else { return nil }
            let qualifiedName = (lookupScopes + [name]).joined(separator: ".")
            let signature = kind == .enumCase ? enumCaseSignature(node, name: nameNode) : signature
            let suffix = signature.map {
                "(" + $0.parameters.map { ($0.argumentLabel ?? "_") + ":" }.joined() + ")"
            }
            return try Declaration(name: name, qualifiedName: qualifiedName,
                                   kind: kind, signature: signature,
                                   callableName: suffix.map { name + $0 },
                                   qualifiedCallableName: suffix.map { qualifiedName + $0 }, enclosingScopes: scopes,
                                   identifierRange: identifierRange, declarationRange: fullRange,
                                   headerRange: header)
        }
    }

    private func headerRange(_ node: SyntaxNode) -> SourceRange? {
        // Only direct declaration children can delimit a body. Closures in attributes,
        // defaults and stored initializers stay inside their expression nodes.
        let children = node.children
        let bodyKinds = ["function_body", "computed_property", "willset_didset_block",
                         "protocol_property_requirements", "class_body", "enum_class_body", "protocol_body"]
        let bodyIndex = children.firstIndex { bodyKinds.contains($0.kind) } ?? children.endIndex
        // A group with bindings after an accessor cannot have one contiguous body-free header.
        guard children.dropFirst(bodyIndex).dropFirst()
            .allSatisfy({ $0.isTrivia || $0.kind == ";" }) else { return nil }
        let header = children[..<bodyIndex].filter { !$0.isTrivia }
        guard !header.contains(where: { $0.hasError || $0.isMissing }),
              let first = header.first, let last = header.last else { return nil }
        return snapshot.range(first.start ..< last.end)
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
        var parameters: [CallableSignature.Parameter] = []
        for index in header.indices where header[index].kind == "parameter" {
            let parameter = header[index]
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
            let labelNode = externalName ?? (defaultsToUnlabeled ? nil : localName)
            let label = labelNode.flatMap { text($0) == "_" ? nil : unescape(text($0)) }
            let name = text(localName) == "_" ? nil : unescape(text(localName))
            // Default expressions are siblings of the parameter, not part of its type node.
            let next = header.suffix(from: header.index(after: index)).first { !$0.isTrivia }
            let isVariadic = children.contains { $0.kind == "..." || $0.kind == "type_pack_expansion" }
            parameters.append(.init(name: name, argumentLabel: label,
                                    typeSyntax: text(typeStart.start ..< typeEnd.end),
                                    passing: isVariadic ? .variadicPositional : .positional,
                                    hasDefaultValue: next?.kind == "="))
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

    private func enumCaseSignature(_ node: SyntaxNode, name: SyntaxNode) -> CallableSignature? {
        // Each case in a group owns only the suffix immediately following its name.
        let suffix = node.children.drop { $0.end <= name.end }.prefix { $0.kind != "," }
            .filter { !$0.isTrivia }
        guard suffix.count == 1, let values = suffix.first, values.kind == "enum_type_parameters",
              !values.hasError else { return nil }
        let children = values.syntaxChildren
        guard children.first?.kind == "(", children.last?.kind == ")" else { return nil }
        // Only direct grammar children delimit values; nested type/default commas stay inside their nodes.
        let parts = children.dropFirst().dropLast().split(omittingEmptySubsequences: false) { $0.kind == "," }
        var parameters: [CallableSignature.Parameter] = []
        for part in parts {
            let annotation = part.prefix { $0.kind != "=" }
            let colon = annotation.firstIndex { $0.kind == ":" }
            let type = colon.map { annotation.suffix(from: annotation.index(after: $0)) } ?? annotation[...]
            guard let first = type.first, let last = type.last else { return nil }
            let label = colon.flatMap { _ in annotation.first }.flatMap { text($0) == "_" ? nil : unescape(text($0)) }
            // Associated values have argument labels, but introduce no local parameter bindings.
            parameters.append(.init(argumentLabel: label, typeSyntax: text(first.start ..< last.end),
                                    hasDefaultValue: part.contains { $0.kind == "=" }))
        }
        return CallableSignature(parameters: parameters)
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
