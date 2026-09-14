import TreeSitterKotlin

/// Extracts per-file Kotlin syntax using Tree-sitter Kotlin 1.1.0 and runtime 0.25.10.
/// Lookup paths are syntactic, without import resolution or type checking.
public struct TreeSitterKotlinExtractor: DeclarationExtractor {
    public init() {}

    public func extract(from snapshot: SourceSnapshot) throws -> ExtractionResult {
        guard snapshot.language == .kotlin else { throw ExtractionError.unsupportedLanguage(snapshot.language) }
        return try TreeSitterParser.extract(from: snapshot, language: tree_sitter_kotlin()) { root in
            var extraction = KotlinSyntaxExtraction(snapshot: snapshot)
            return try extraction.extract(root: root)
        }
    }
}

private struct KotlinSyntaxExtraction {
    struct Context {
        var scopes: [String] = []
        var path = ""
        var isMember = false
        var isLocal = false

        func qualify(_ name: String) -> String {
            path.isEmpty ? name : path + "." + name
        }

        func nested(_ name: String, lookup: String) -> Context {
            Context(scopes: scopes + [name], path: qualify(lookup), isLocal: true)
        }
    }

    let snapshot: SourceSnapshot
    let bytes: [UInt8]
    var declarations: [Declaration] = []
    var diagnostics: [ParseDiagnostic] = []

    init(snapshot: SourceSnapshot) {
        self.snapshot = snapshot
        bytes = Array(snapshot.text.utf8)
    }

    mutating func extract(root: SyntaxNode) throws -> ExtractionResult {
        let package = root.children.first { $0.kind == "package_header" }
        let packageName = package.flatMap { node in
            node.hasError ? nil : node.children.first { $0.kind == "qualified_identifier" }.map(lookupSpelling)
        }
        var stack = [(root, Context(path: packageName ?? ""))]
        while let (node, inherited) = stack.popLast() {
            let children = node.children
            recordDiagnostic(node, children: children)
            var context = inherited
            if ["class_body", "enum_class_body"].contains(node.kind) {
                context.isMember = true
                context.isLocal = false
            } else if ["block", "function_body", "lambda_literal", "anonymous_function"].contains(node.kind) {
                context.isMember = false
                context.isLocal = true
            }
            let nested = try extractDeclaration(node, context: context)
            stack.append(contentsOf: children.reversed().map { ($0, nested) })
        }
        return try ExtractionResult(snapshot: snapshot, declarations: declarations, diagnostics: diagnostics)
    }

    private mutating func recordDiagnostic(_ node: SyntaxNode, children: [SyntaxNode]) {
        if node.isError || node.isMissing {
            diagnostics.append(.init(severity: .error,
                                     message: node.isMissing ? "Tree-sitter: missing \(node.kind)"
                                         : "Tree-sitter: unrecognized syntax",
                                     range: snapshot.range(node.offsets)))
        } else if node.hasError, !children.contains(where: \.hasError) {
            diagnostics.append(.init(severity: .error, message: "Tree-sitter: recovered syntax in \(node.kind)",
                                     range: snapshot.range(node.offsets)))
        }
    }

    private mutating func extractDeclaration(_ node: SyntaxNode, context: Context) throws -> Context {
        switch node.kind {
        case "class_declaration", "object_declaration", "companion_object":
            let identifier = node.field("name") ?? (node.kind == "companion_object" ? child(node, "object") : nil)
            guard let identifier else { return context }
            let name = node.kind == "companion_object" && node.field("name") == nil
                ? "Companion" : unescape(text(identifier))
            return try append(node, identifier: identifier, name: name, kind: .type, context: context)
        case "function_declaration":
            guard let identifier = node.field("name") else { return context }
            return try append(node, identifier: identifier, kind: context.isMember ? .method : .function,
                              context: context, receiver: receiver(node, before: identifier))
        case "secondary_constructor", "anonymous_initializer":
            let keyword = node.kind == "secondary_constructor" ? "constructor" : "init"
            guard let identifier = child(node, keyword) else { return context }
            return try append(node, identifier: identifier, kind: .initializer, context: context)
        case "type_alias":
            guard let identifier = node.field("type") else { return context }
            return try append(node, identifier: identifier, kind: .typeAlias, context: context)
        case "enum_entry":
            guard let identifier = child(node, "identifier") else { return context }
            return try append(node, identifier: identifier, kind: .enumCase, context: context)
        case "class_parameter":
            guard child(node, "val") != nil || child(node, "var") != nil,
                  let identifier = child(node, "identifier") else { return context }
            return try append(node, identifier: identifier, kind: .property, context: context)
        case "property_declaration":
            return try extractProperty(node, context: context)
        case "when_subject":
            guard child(node, "val") != nil, let binding = child(node, "variable_declaration"),
                  let identifier = child(binding, "identifier"), text(identifier) != "_" else { return context }
            return try append(node, identifier: identifier, kind: .variable, context: context)
        default:
            return context
        }
    }

    private mutating func extractProperty(_ node: SyntaxNode, context: Context) throws -> Context {
        let group = child(node, "multi_variable_declaration")
        let bindings = group?.children.filter { $0.kind == "variable_declaration" }
            ?? node.children.filter { $0.kind == "variable_declaration" }
        var nested = context
        for binding in bindings {
            guard let identifier = child(binding, "identifier"), text(identifier) != "_" else { continue }
            nested = try append(node, identifier: identifier, kind: context.isLocal ? .variable : .property,
                                context: context, receiver: receiver(node, before: group ?? binding))
        }
        // A destructuring initializer has no single owner. Its declarations remain local.
        if group != nil {
            var anonymous = context
            anonymous.isMember = false
            anonymous.isLocal = true
            return anonymous
        }
        return nested
    }

    private mutating func append(_ node: SyntaxNode, identifier: SyntaxNode, name suppliedName: String? = nil,
                                 kind: Declaration.Kind, context: Context, receiver: String? = nil) throws -> Context
    {
        guard !identifier.hasError, !identifier.isMissing, identifier.end > identifier.start,
              let identifierRange = snapshot.range(identifier.offsets),
              let start = syntaxToken(in: declarationChildren(node), fromEnd: false)?.start,
              let end = syntaxToken(in: declarationChildren(node), fromEnd: true)?.end,
              let fullRange = snapshot.range(start ..< end) else { return context }
        let name = suppliedName ?? unescape(text(identifier))
        let lookup = receiver.map { $0 + "." + name } ?? name
        let header = headerRange(node)
        let signature = header == nil ? nil : callableSignature(node)
        try declarations.append(Declaration(name: name, qualifiedName: context.qualify(lookup), kind: kind,
                                            signature: signature, enclosingScopes: context.scopes,
                                            identifierRange: identifierRange, declarationRange: fullRange,
                                            headerRange: header))
        return context.nested(name, lookup: lookup)
    }

    private func headerRange(_ node: SyntaxNode) -> SourceRange? {
        guard !hasDetachedInitializerError(node) else { return nil }
        let boundaries = ["class_body", "enum_class_body", "function_body", "block", "getter", "setter"]
        let header = declarationChildren(node).prefix { !boundaries.contains($0.kind) }
            .filter { !isTrivia($0) && $0.kind != ";" }
        guard !header.isEmpty, !header.contains(where: { $0.hasError || $0.isMissing }),
              let first = header.first, let last = header.last,
              let start = syntaxBoundary(first, fromEnd: false),
              let end = syntaxBoundary(last, fromEnd: true) else { return nil }
        return snapshot.range(start ..< end)
    }

    private func declarationChildren(_ node: SyntaxNode) -> [SyntaxNode] {
        // The when parentheses enclose the subject expression, not its val declaration.
        node.children.filter { node.kind != "when_subject" || ($0.kind != "(" && $0.kind != ")") }
    }

    private func hasDetachedInitializerError(_ node: SyntaxNode) -> Bool {
        guard ["property_declaration", "class_parameter"].contains(node.kind),
              !node.children.contains(where: { [";", "getter", "setter"].contains($0.kind) }) else { return false }
        var end = node.end
        var sibling = node.nextSibling
        while let next = sibling {
            // Kotlin can hide an explicit statement separator between sibling nodes.
            guard !bytes[end ..< next.start].contains(59) else { return false }
            if isTrivia(next) {
                end = next.end
                sibling = next.nextSibling
                continue
            }
            guard next.isError, let token = syntaxToken(in: [next], fromEnd: false) else { return false }
            // Recovery may detach a missing stored/delegated initializer from its owner.
            return ["=", "by"].contains(text(token))
        }
        return false
    }

    private func callableSignature(_ node: SyntaxNode) -> CallableSignature? {
        // Primary constructors are represented on the class, without inventing an identifier.
        let list: SyntaxNode?
        switch node.kind {
        case "class_declaration": list = child(node, "primary_constructor").flatMap { child($0, "class_parameters") }
        case "function_declaration", "secondary_constructor": list = child(node, "function_value_parameters")
        default: return nil
        }
        guard let list, !list.hasError, let parameters = parameters(list) else { return nil }
        let children = node.children
        let colon = children.firstIndex { $0.kind == ":" && $0.start >= list.end }
        let returnType = node.kind == "function_declaration" ? colon.flatMap { index in
            children.dropFirst(index + 1).first { !isTrivia($0) }.map(text)
        } : nil
        let effects = child(node, "modifiers")?.children.filter {
            $0.kind == "function_modifier" && text($0) == "suspend"
        }.map(text) ?? []
        return CallableSignature(parameters: parameters, genericParameters: child(node, "type_parameters").map(text),
                                 effects: effects, returnType: returnType,
                                 genericConstraints: child(node, "type_constraints").map(text))
    }

    private func parameters(_ list: SyntaxNode) -> [CallableSignature.Parameter]? {
        let children = list.children.filter { !isTrivia($0) }
        var result: [CallableSignature.Parameter] = []
        for (index, parameter) in children.enumerated()
            where ["parameter", "class_parameter"].contains(parameter.kind)
        {
            let parts = parameter.children.filter { !isTrivia($0) }
            guard let identifier = parts.first(where: { $0.kind == "identifier" }),
                  let colon = parts.firstIndex(where: { $0.kind == ":" }), colon + 1 < parts.count else { return nil }
            let modifiers = parameter.kind == "class_parameter" ? child(parameter, "modifiers")
                : (index > 0 && children[index - 1].kind == "parameter_modifiers" ? children[index - 1] : nil)
            let variadic = modifiers?.children.contains {
                $0.kind == "parameter_modifier" && text($0) == "vararg"
            } ?? false
            let hasDefault = parameter.kind == "class_parameter" ? parts.contains { $0.kind == "=" }
                : (index + 1 < children.count && children[index + 1].kind == "=")
            let name = unescape(text(identifier))
            result.append(.init(name: name, argumentLabel: name, typeSyntax: text(parts[colon + 1]),
                                passing: variadic ? .variadicPositional : .positional, hasDefaultValue: hasDefault))
        }
        return result
    }

    private func receiver(_ node: SyntaxNode, before name: SyntaxNode) -> String? {
        // Receiver nodes precede the name/binding, while result types follow it.
        let types = ["user_type", "nullable_type", "parenthesized_type", "dynamic"]
        let children = node.children.filter { !isTrivia($0) }
        guard let index = children.firstIndex(where: {
            $0.end <= name.start && types.contains($0.kind) && !$0.hasError
        }) else { return nil }
        // The grammar can expose receiver modifiers beside the type rather than inside it.
        let start = index > 0 && children[index - 1].kind == "type_modifiers" ? index - 1 : index
        let receiver = children[start ... index]
        guard !receiver.contains(where: \.hasError) else { return nil }
        return receiver.map(lookupSpelling).joined()
    }

    private func child(_ node: SyntaxNode, _ kind: String) -> SyntaxNode? {
        node.children.first { $0.kind == kind }
    }

    private func isTrivia(_ node: SyntaxNode) -> Bool {
        ["line_comment", "block_comment", "shebang"].contains(node.kind)
    }

    private func syntaxBoundary(_ node: SyntaxNode, fromEnd: Bool) -> Int? {
        syntaxToken(in: [node], fromEnd: fromEnd).map { fromEnd ? $0.end : $0.start }
    }

    private func syntaxToken(in nodes: [SyntaxNode], fromEnd: Bool) -> SyntaxNode? {
        var stack = fromEnd ? nodes : nodes.reversed()
        while let candidate = stack.popLast() {
            guard !isTrivia(candidate), !candidate.isMissing, candidate.end > candidate.start else { continue }
            let children = candidate.children
            if children.isEmpty {
                return candidate
            }
            stack.append(contentsOf: fromEnd ? children : children.reversed())
        }
        return nil
    }

    private func lookupSpelling(_ node: SyntaxNode) -> String {
        var stack = [node]
        var tokens: [String] = []
        while let candidate = stack.popLast() {
            guard !isTrivia(candidate), !candidate.isMissing else { continue }
            let children = candidate.children
            if children.isEmpty {
                tokens.append(unescape(text(candidate)))
            } else {
                stack.append(contentsOf: children.reversed())
            }
        }
        return tokens.joined()
    }

    private func unescape(_ name: String) -> String {
        name.hasPrefix("`") && name.hasSuffix("`") ? String(name.dropFirst().dropLast()) : name
    }

    private func text(_ node: SyntaxNode) -> String {
        String(decoding: bytes[node.offsets], as: UTF8.self)
    }
}
