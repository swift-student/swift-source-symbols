import TreeSitterRuby

/// Extracts per-file Ruby syntax using Tree-sitter Ruby 0.23.1 and runtime 0.25.10.
/// Qualification describes syntax, not Ruby's runtime constant lookup or method dispatch.
public struct TreeSitterRubyExtractor: DeclarationExtractor {
    public init() {}

    public func extract(from snapshot: SourceSnapshot) throws -> ExtractionResult {
        guard snapshot.language == .ruby else { throw ExtractionError.unsupportedLanguage(snapshot.language) }
        return try TreeSitterParser.extract(from: snapshot, language: tree_sitter_ruby()) { root in
            var extraction = RubySyntaxExtraction(snapshot: snapshot)
            return try extraction.extract(root: root)
        }
    }
}

private struct RubySyntaxExtraction {
    struct Context {
        var scopes: [String] = []
        var namespace = ""
        var instanceOwner: String?
        var singletonOwner: String?
        var selfReceiver = "self"

        func qualify(_ name: String) -> String {
            name.hasPrefix("::") || namespace.isEmpty ? name : namespace + "::" + name
        }
    }

    struct Work {
        let node: SyntaxNode
        var context: Context
        var heredocs: [SyntaxNode] = []
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
        var stack = [Work(node: root, context: Context())]
        while let work = stack.popLast() {
            let node = work.node
            let children = childWork(work)
            recordDiagnostic(node, children: node.children)
            let bodyContext = try extractDeclaration(node, context: work.context, children: children,
                                                     trailingEnd: work.heredocs.last?.end)
            let body = node.field("body")
            let parameters = node.field("parameters")
            for var child in children.reversed() {
                let isBody = body?.offsets == child.node.offsets && body?.kind == child.node.kind
                let isParameters = parameters?.offsets == child.node.offsets && parameters?.kind == child.node.kind
                if isBody || isParameters {
                    child.context = bodyContext
                }
                stack.append(child)
            }
        }
        return try ExtractionResult(snapshot: snapshot, declarations: declarations, diagnostics: diagnostics)
    }

    private func childWork(_ work: Work) -> [Work] {
        let nodes = work.node.children + work.heredocs
        let hasDelayedBodies = nodes.contains { $0.kind == "heredoc_body" }
        var children: [Work] = []
        var pending: [(index: Int, count: Int)] = []
        var nextPending = 0
        for child in nodes {
            // Delayed bodies belong to the statements containing their opening tokens,
            // which need not be the immediately preceding statement on the same line.
            if child.kind == "heredoc_body", nextPending < pending.count {
                children[pending[nextPending].index].heredocs.append(child)
                pending[nextPending].count -= 1
                if pending[nextPending].count == 0 {
                    nextPending += 1
                }
                continue
            }
            children.append(Work(node: child, context: work.context))
            if hasDelayedBodies {
                let count = pendingHeredocs(child)
                if count > 0 {
                    pending.append((children.count - 1, count))
                }
            }
        }
        return children
    }

    private func pendingHeredocs(_ node: SyntaxNode) -> Int {
        var stack = [node]
        var count = 0
        while let next = stack.popLast() {
            if next.kind == "heredoc_beginning" {
                count += 1
            }
            if next.kind == "heredoc_body" {
                count -= 1
            }
            stack.append(contentsOf: next.children)
        }
        return count
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

    private mutating func extractDeclaration(_ node: SyntaxNode, context: Context, children: [Work],
                                             trailingEnd: Int?) throws -> Context
    {
        switch node.kind {
        case "class", "module":
            guard let path = node.field("name"), let names = constantPath(path, context: context),
                  let nameNode = path.kind == "constant" ? path : path.field("name") else { return context }
            guard try append(node, identifier: nameNode, name: text(nameNode), qualified: names.qualified,
                             kind: .type, context: context, trailingEnd: trailingEnd,
                             headerRange: headerRange(node, through: node.field("superclass") ?? path,
                                                      children: children))
            else { return context }
            return Context(scopes: context.scopes + [names.spelling], namespace: names.qualified,
                           instanceOwner: names.qualified, selfReceiver: names.qualified)
        case "singleton_class":
            guard let value = node.field("value"), !value.hasError, !value.isMissing else { return context }
            let owner = receiver(value, context: context)
            let name = "<< " + text(value)
            let qualified = context.qualify(name)
            guard try append(node, identifier: value, name: name, qualified: qualified,
                             kind: .extensionScope, context: context, trailingEnd: trailingEnd,
                             headerRange: headerRange(node, through: value, children: children)) else { return context }
            return Context(scopes: context.scopes + [name], namespace: qualified,
                           singletonOwner: owner, selfReceiver: owner + ".singleton_class")
        case "method", "singleton_method":
            return try extractMethod(node, context: context, children: children, trailingEnd: trailingEnd)
        case "assignment", "operator_assignment":
            if let left = node.field("left") {
                for path in constantBindings(left) {
                    guard let names = constantPath(path, context: context),
                          let nameNode = path.kind == "constant" ? path : path.field("name") else { continue }
                    try append(node, identifier: nameNode, name: text(nameNode), qualified: names.qualified,
                               kind: .variable, context: context, trailingEnd: trailingEnd)
                }
            }
            return context
        case "alias":
            if let nameNode = node.field("name"),
               ["identifier", "constant", "operator", "setter", "simple_symbol"].contains(nameNode.kind)
            {
                let name = nameNode.kind == "simple_symbol" ? String(text(nameNode).dropFirst()) : text(nameNode)
                try append(node, identifier: nameNode, name: name, qualified: methodName(name, context: context),
                           kind: .method, context: context, trailingEnd: trailingEnd,
                           headerRange: headerRange(node, through: node, children: children))
            }
            return context
        default:
            return context
        }
    }

    private mutating func extractMethod(_ node: SyntaxNode, context: Context, children: [Work],
                                        trailingEnd: Int?) throws -> Context
    {
        guard let nameNode = node.field("name") else { return context }
        let name = text(nameNode)
        let qualified: String
        if node.kind == "singleton_method" {
            guard let object = node.field("object"), !object.hasError, !object.isMissing else { return context }
            qualified = receiver(object, context: context) + "." + name
        } else {
            qualified = methodName(name, context: context)
        }
        let signature = callableSignature(node, children: children)
        let header = headerRange(node, through: node.field("parameters") ?? nameNode, children: children)
        guard try append(node, identifier: nameNode, name: name, qualified: qualified,
                         kind: .method, signature: signature, context: context, trailingEnd: trailingEnd,
                         headerRange: header)
        else { return context }
        // A nested def is retained lexically, without inferring the receiver of runtime self.
        return Context(scopes: context.scopes + [name], namespace: qualified,
                       selfReceiver: qualified + "::self")
    }

    @discardableResult
    private mutating func append(_ node: SyntaxNode, identifier: SyntaxNode, name: String,
                                 qualified: String, kind: Declaration.Kind, signature: CallableSignature? = nil,
                                 context: Context, trailingEnd: Int?, headerRange: SourceRange? = nil) throws -> Bool
    {
        guard !identifier.hasError, !identifier.isMissing, identifier.end > identifier.start,
              let identifierRange = snapshot.range(identifier.offsets),
              let start = syntaxBoundary(node, fromEnd: false),
              let end = syntaxBoundary(node, fromEnd: true),
              let declarationRange = snapshot.range(start ..< max(end, trailingEnd ?? end)) else { return false }
        // Ruby uses method names directly for lookup; signatures do not invent a second spelling.
        try declarations.append(Declaration(name: name, qualifiedName: qualified, kind: kind,
                                            signature: signature, enclosingScopes: context.scopes,
                                            identifierRange: identifierRange, declarationRange: declarationRange,
                                            headerRange: headerRange))
        return true
    }

    private func headerRange(_ node: SyntaxNode, through last: SyntaxNode, children: [Work]) -> SourceRange? {
        guard headerIsReliable(node, through: last, children: children) else { return nil }
        let header = node.children.filter { $0.start < last.end && !isTrivia($0) }
        guard !header.contains(where: { $0.hasError || $0.isMissing }) else { return nil }
        var stack = header
        while let child = stack.popLast() {
            // A heredoc's delayed text cannot be included without potentially including a body.
            guard child.kind != "heredoc_beginning" else { return nil }
            stack.append(contentsOf: child.children)
        }
        return snapshot.range(node.start ..< last.end)
    }

    private func headerIsReliable(_ node: SyntaxNode, through last: SyntaxNode, children: [Work]) -> Bool {
        let list = node.field("parameters")
        let headerEnd = last.end
        let body = node.field("body")
        let closingParenthesis = list?.children.last { !isTrivia($0) }
        let hasClosedParameters = closingParenthesis?.kind == ")" && closingParenthesis?.isMissing == false
        for work in children where work.node.kind != "end" && !isTrivia(work.node) {
            let child = work.node
            if body?.kind == child.kind, body?.offsets == child.offsets {
                break
            }
            if child.start >= headerEnd {
                // Ruby permits a body immediately after a complete parenthesized parameter list.
                if hasClosedParameters {
                    break
                }
                // A line break, semicolon, or endless-body '=' separates a sound header from body recovery.
                if bytes[headerEnd ..< child.start].contains(where: { [10, 13, 59, 61].contains($0) }) {
                    break
                }
                if child.kind == ";" || child.kind == "=" {
                    break
                }
            }
            // Delayed default expressions are header syntax even when their bodies lie after `end`.
            if child.hasError || child.isMissing || work.heredocs.contains(where: \.hasError) {
                return false
            }
        }
        return true
    }

    private func callableSignature(_ node: SyntaxNode, children: [Work]) -> CallableSignature? {
        let list = node.field("parameters")
        guard let last = list ?? node.field("name"),
              headerIsReliable(node, through: last, children: children) else { return nil }
        guard let list else { return CallableSignature(parameters: []) }
        var parameters: [CallableSignature.Parameter] = []
        for parameter in list.children
            where !isTrivia(parameter) && !["(", ")", ",", "heredoc_body"].contains(parameter.kind)
        {
            guard let metadata = parameterMetadata(parameter) else { return nil }
            parameters.append(metadata)
        }
        return CallableSignature(parameters: parameters)
    }

    private func parameterMetadata(_ node: SyntaxNode) -> CallableSignature.Parameter? {
        let name = node.field("name").map(text)
        switch node.kind {
        case "identifier": return .init(name: text(node))
        case "optional_parameter": return .init(name: name, hasDefaultValue: true)
        case "keyword_parameter":
            return .init(name: name, argumentLabel: name, passing: .keyword,
                         hasDefaultValue: node.field("value") != nil)
        case "splat_parameter": return .init(name: name, passing: .variadicPositional)
        case "hash_splat_parameter": return .init(name: name, passing: .variadicKeyword)
        case "block_parameter": return .init(name: name, passing: .block)
        // The core does not represent destructuring structure, forwarding, or keyword rejection.
        // Omit the signature instead of equating distinct headers or inventing zero arity.
        default: return nil
        }
    }

    private func methodName(_ name: String, context: Context) -> String {
        if let owner = context.singletonOwner {
            return owner + "." + name
        }
        if let owner = context.instanceOwner {
            return owner + "#" + name
        }
        return context.qualify(name)
    }

    private func constantBindings(_ node: SyntaxNode) -> [SyntaxNode] {
        if node.kind == "constant" || node.kind == "scope_resolution" {
            return [node]
        }
        guard ["left_assignment_list", "destructured_left_assignment", "rest_assignment"].contains(node.kind)
        else { return [] }
        return node.children.flatMap(constantBindings)
    }

    private func constantPath(_ node: SyntaxNode, context: Context) -> (spelling: String, qualified: String)? {
        guard !node.hasError, !node.isMissing else { return nil }
        if node.kind == "constant" {
            let spelling = text(node)
            return (spelling, context.qualify(spelling))
        }
        guard node.kind == "scope_resolution", let name = node.field("name") else { return nil }
        if let scope = node.field("scope") {
            let prefix = constantPath(scope, context: context)
                ?? (receiverSpelling(scope), receiver(scope, context: context))
            return (prefix.spelling + "::" + text(name), prefix.qualified + "::" + text(name))
        }
        let spelling = "::" + text(name)
        return (spelling, spelling)
    }

    private func receiver(_ node: SyntaxNode, context: Context) -> String {
        if node.kind == "self" {
            return context.selfReceiver
        }
        if let path = constantPath(node, context: context) {
            return path.qualified
        }
        // Keep arbitrary receiver expressions explicit; they have no statically known identity.
        return context.qualify(receiverSpelling(node))
    }

    private func receiverSpelling(_ node: SyntaxNode) -> String {
        node.children.isEmpty ? text(node) : "(" + text(node) + ")"
    }

    private func isTrivia(_ node: SyntaxNode) -> Bool {
        node.kind == "comment"
    }

    private func syntaxBoundary(_ node: SyntaxNode, fromEnd: Bool) -> Int? {
        var stack = [node]
        while let candidate = stack.popLast() {
            guard !isTrivia(candidate), !candidate.isMissing, candidate.end > candidate.start else { continue }
            let children = candidate.children
            if !candidate.hasError || children.isEmpty {
                return fromEnd ? candidate.end : candidate.start
            }
            stack.append(contentsOf: fromEnd ? children : children.reversed())
        }
        return nil
    }

    private func text(_ node: SyntaxNode) -> String {
        String(decoding: bytes[node.offsets], as: UTF8.self)
    }
}
