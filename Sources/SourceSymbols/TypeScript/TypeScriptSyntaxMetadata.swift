extension TypeScriptSyntaxExtraction {
    func signature(_ node: SyntaxNode) -> CallableSignature? {
        guard headerRange(node, owner: node) != nil else { return nil }
        let parameters: [CallableSignature.Parameter]
        if let list = node.field("parameters") {
            let nodes = list.children.filter { !["(", ")", ",", "comment"].contains($0.kind) }
            let metadata = nodes.compactMap(parameterMetadata)
            guard metadata.count == nodes.count else { return nil }
            parameters = metadata
        } else if let parameter = node.field("parameter"), healthy(parameter), parameter.kind == "identifier" {
            parameters = [.init(name: text(parameter))]
        } else {
            return nil
        }
        let effects = node.children.filter { ["async", "*"].contains($0.kind) }.map(text)
        return CallableSignature(parameters: parameters, genericParameters: node.field("type_parameters").map(text),
                                 effects: effects, returnType: node.field("return_type").flatMap(annotation))
    }

    private func parameterMetadata(_ node: SyntaxNode) -> CallableSignature.Parameter? {
        guard ["required_parameter", "optional_parameter"].contains(node.kind),
              healthy(node), let pattern = node.field("pattern") else { return nil }
        // TypeScript's explicit `this` pseudo-parameter is not a supplied argument.
        // The shared model has no receiver channel; retain the header but omit this signature.
        guard pattern.kind != "this" else { return nil }
        let rest = pattern.kind == "rest_pattern"
        let binding = rest ? pattern.children.first(where: { $0.kind != "..." && $0.kind != "comment" }) : pattern
        let name = binding.flatMap { $0.kind == "identifier" ? text($0) : nil }
        return .init(name: name, typeSyntax: node.field("type").flatMap(annotation),
                     passing: rest ? .variadicPositional : .positional,
                     hasDefaultValue: node.field("value") != nil, isOptional: node.kind == "optional_parameter")
    }

    private func annotation(_ node: SyntaxNode) -> String? {
        // Annotation nodes own the colon; only the actual type/predicate is metadata.
        let syntax = node.children.filter { $0.kind != ":" && $0.kind != "comment" }
        guard let first = syntax.first, let last = syntax.last else { return nil }
        return String(decoding: bytes[first.start ..< last.end], as: UTF8.self)
    }

    func callableValue(_ node: SyntaxNode?) -> SyntaxNode? {
        guard let node else { return nil }
        if ["arrow_function", "function_expression", "generator_function"].contains(node.kind) {
            return node
        }
        if node.kind == "parenthesized_expression" {
            let children = node.children.filter { !["(", ")", "comment"].contains($0.kind) }
            return children.count == 1 ? callableValue(children.first) : nil
        }
        return nil
    }

    func headerRange(_ node: SyntaxNode, owner: SyntaxNode) -> SourceRange? {
        let body = node.field("body")
        let syntax = node.children.prefix { !same($0, body) }
            .filter { !["comment", ";", "=>"].contains($0.kind) }
        let end: Int? = if node.children.isEmpty {
            healthy(node) ? node.end : nil
        } else {
            syntax.last.flatMap { boundary($0, fromEnd: true) }
        }
        guard let start = boundary(owner, fromEnd: false), let end, end >= start else { return nil }
        // Inspect only the prefix; a recognized body's errors cannot damage a sound header.
        var stack = [owner]
        while let child = stack.popLast() {
            guard child.start <= end else { continue }
            if same(child, body) || child.kind == "comment" {
                continue
            }
            let children = child.children
            if child.isError || child.isMissing || (child.hasError && !children.contains(where: \.hasError)) {
                return nil
            }
            stack.append(contentsOf: children.filter { $0.start < end || ($0.start == end && $0.isMissing) })
        }
        return snapshot.range(start ..< end)
    }

    func boundary(_ node: SyntaxNode, fromEnd: Bool) -> Int? {
        var stack = [node]
        while let candidate = stack.popLast() {
            guard candidate.kind != "comment", !candidate.isMissing, candidate.end > candidate.start else { continue }
            let children = candidate.children
            if children.isEmpty {
                return fromEnd ? candidate.end : candidate.start
            }
            stack.append(contentsOf: fromEnd ? children : children.reversed())
        }
        return nil
    }

    func diagnostics(in root: SyntaxNode) -> [ParseDiagnostic] {
        var result: [ParseDiagnostic] = []
        var stack = [root]
        while let node = stack.popLast() {
            let children = node.children
            if node.isError || node.isMissing {
                result.append(.init(severity: .error,
                                    message: node.isMissing ? "Tree-sitter: missing \(node.kind)"
                                        : "Tree-sitter: unrecognized syntax",
                                    range: snapshot.range(node.offsets)))
            } else if node.hasError, !children.contains(where: \.hasError) {
                result.append(.init(severity: .error, message: "Tree-sitter: recovered syntax in \(node.kind)",
                                    range: snapshot.range(node.offsets)))
            }
            stack.append(contentsOf: children.reversed())
        }
        return result
    }
}
