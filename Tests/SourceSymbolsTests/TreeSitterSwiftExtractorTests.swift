import Foundation
import SourceSymbols
import Testing

func fixture(_ name: String) throws -> SourceSnapshot {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "swift", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    return try SourceSnapshot(text: #require(String(data: data, encoding: .utf8)), language: .swift)
}

private struct ExpectedFixture: Decodable {
    let declarations: [ExpectedDeclaration]
    let diagnosticRanges: [[Int]]
    let qualifiedNames: [String]
    let callableNames: [String?]?
    let qualifiedCallableNames: [String?]?
}

@Test(arguments: ["declarations", "callables", "trivia", "conditional", "unicode-lf", "unicode-crlf", "representative",
                  "enum-associated-values", "callable-scopes"])
func declarationCorpus(name: String) throws {
    let snapshot = try fixture(name)
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    let expected = try JSONDecoder().decode(ExpectedFixture.self, from: Data(contentsOf: url))
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    try expectBackendContract(result, from: snapshot, declarations: expected.declarations,
                              diagnosticRanges: expected.diagnosticRanges.map { $0[0] ..< $0[1] })
    #expect(result.declarations.map(\.qualifiedName) == expected.qualifiedNames)
    if let names = expected.callableNames {
        #expect(result.declarations.map(\.callableName) == names)
    }
    if let names = expected.qualifiedCallableNames {
        #expect(result.declarations.map(\.qualifiedCallableName) == names)
    }
}

func candidates(_ query: DeclarationQuery, in result: ExtractionResult) -> [Declaration] {
    switch DeclarationMatcher.match(query, in: result.declarations) {
    case .missing: []
    case let .unique(declaration): [declaration]
    case let .ambiguous(declarations): declarations
    }
}

@Test func extractedOverloadsPreserveAmbiguityAndOrder() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("declarations"))
    let all = candidates(.init(name: .short("run")), in: result)
    #expect(all.count == 6)
    #expect(all.map(\.qualifiedName) == [
        "Store.run",
        "Store.run",
        "Store.run",
        "Store.run",
        "Store.Nested.run",
        "Runnable.run",
    ])
    let scoped = candidates(.init(name: .qualified("Store.run(value:)")), in: result)
    #expect(scoped.map { $0.signature?.parameters.map(\.typeSyntax) } == [["Int"], ["String"]])
    expectMatches(.init(name: .qualified("Store.run(value:)")), in: result,
                  identifierOffsets: [105 ..< 108, 133 ..< 136])
    expectMatches(.init(name: .qualified("Store.run(value:)"), parameterTypes: ["String"]), in: result,
                  identifierOffsets: [133 ..< 136])
    #expect(candidates(.init(name: .qualified("Store.run(other:)")), in: result).count == 1)
    #expect(candidates(.init(name: .short("run()")), in: result).count == 1)
    #expect(candidates(.init(name: .short("Run")), in: result).isEmpty)
    expectMatches(.init(name: .short("missing")), in: result, identifierOffsets: [])
    #expect(candidates(.init(name: .short("run(value:)"), parameterTypes: ["Bool"]), in: result).isEmpty)
}

@Test func structuredSignaturesUseSyntaxNotCommaSplitting() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("callables"))
    let convert = try #require(candidates(.init(name: .short("convert(_:into:)")), in: result).first)
    #expect(convert.signature == CallableSignature(
        parameters: [.init(name: "transform", typeSyntax: "@escaping (T, Int) throws -> U", hasDefaultValue: true),
                     .init(name: "values", argumentLabel: "into", typeSyntax: "inout [U]")],
        genericParameters: "<T, U>", effects: ["async", "throws"], returnType: "[U]",
        genericConstraints: "where U: Equatable"
    ))
    #expect(candidates(
        .init(name: .short("pair(value:done:)"), parameterTypes: ["(Int, String)", "() -> Void"]),
        in: result
    ).count == 1)
    #expect(candidates(.init(name: .short("gather(values:)"), parameterTypes: ["Int..."]), in: result).count == 1)
    #expect(candidates(.init(name: .short("typed(value:)")), in: result).first?.signature?
        .effects == ["throws(Failure)"])
    #expect(candidates(.init(name: .short("call(_:)")), in: result).first?.signature?.effects == ["rethrows"])
    #expect(candidates(.init(name: .short("qualified(value:)"), parameterTypes: ["Int"]), in: result).isEmpty)
    #expect(candidates(.init(name: .short("qualified(value:)"), parameterTypes: ["Swift.Int"]), in: result).count == 1)
    #expect(candidates(.init(name: .qualified("Number.+(_:_:)")), in: result).count == 1)
    #expect(candidates(.init(name: .qualified("Number.==(_:_:)")), in: result).count == 1)
    #expect(candidates(.init(name: .qualified("Number.init(value:)")), in: result).count == 1)
    #expect(candidates(.init(name: .qualified("Number.subscript(key:)")), in: result).count == 1)
    #expect(candidates(.init(name: .qualified("Lifetime.deinit()")), in: result).count == 1)
}

@Test func returnTypesAndConstraintsCanDisambiguate() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("callables"))
    #expect(candidates(.init(name: .short("choose(value:)"), parameterTypes: ["Int"]), in: result).count == 2)
    let signature = CallableSignature(
        parameters: [.init(name: "value", argumentLabel: "value", typeSyntax: "Int")],
        returnType: "String"
    )
    #expect(candidates(.init(name: .short("choose(value:)"), signature: signature), in: result).count == 1)
    let identities = candidates(.init(name: .short("identity(value:)")), in: result)
    #expect(identities.count == 2)
    let constrained = try #require(identities.first?.signature)
    #expect(candidates(.init(name: .short("identity(value:)"), signature: constrained), in: result).count == 1)
}

@Test func rangesIncludeAttributesButExcludeSurroundingTrivia() throws {
    let snapshot = try fixture("trivia")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    let method = try #require(candidates(.init(name: .qualified("Example.run(value:)")), in: result).first)
    #expect(snapshot.text(in: method.identifierRange) == "run")
    #expect(snapshot.text(in: method.declarationRange) == """
    @available(*, deprecated)
        public func run(/* inside */ value: Int) { /* body */ }
    """)
    let property = try #require(candidates(.init(name: .qualified("Example.count")), in: result).first)
    #expect(snapshot.text(in: property.declarationRange) == "public var count: Int = 0")
}

@Test func extensionsAndConditionalBranchesStayDistinct() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("declarations"))
    let nested = candidates(.init(name: .qualified("Store.Nested")), in: result)
    #expect(nested.map(\.kind) == [.type, .extensionScope])
    #expect(candidates(.init(name: .qualified("Store.subscript(_:)")), in: result).count == 1)
    #expect(candidates(.init(name: .qualified("outer().local")), in: result).first?.kind == .variable)
    #expect(candidates(.init(name: .qualified("outer().inner()")), in: result).first?.kind == .function)
    let conditional = try TreeSitterSwiftExtractor().extract(from: fixture("conditional"))
    #expect(candidates(.init(name: .short("Choice")), in: conditional).count == 2)
    #expect(candidates(.init(name: .qualified("Choice.a()")), in: conditional).count == 1)
    #expect(candidates(.init(name: .qualified("Choice.b()")), in: conditional).count == 1)
}

@Test(arguments: ["unicode-lf", "unicode-crlf"])
func unicodeIdentifiersAndEscaping(name: String) throws {
    let snapshot = try fixture(name)
    #expect(snapshot.text.utf8.contains(13) == (name == "unicode-crlf"))
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    let escaped = try #require(candidates(.init(name: .qualified("Café.repeat(for:)")), in: result).first)
    #expect(snapshot.text(in: escaped.identifierRange) == "`repeat`")
    let emoji = try #require(candidates(.init(name: .qualified("Café.😀")), in: result).first)
    #expect(emoji.identifierRange.utf8Offsets.count == 4)
    #expect(snapshot.utf16Offsets(for: emoji.identifierRange)?.count == 2)
}

@Test func utf16ConversionsRejectInvalidAndForeignOffsets() throws {
    let snapshot = SourceSnapshot(text: "a😀e\u{301}\r\n", language: .swift)
    let emoji = try #require(snapshot.range(1 ..< 5))
    #expect(snapshot.utf16Offsets(for: emoji) == 1 ..< 3)
    #expect(snapshot.range(utf16Offsets: 1 ..< 3) == emoji)
    #expect(snapshot.range(utf16Offsets: 2 ..< 3) == nil)
    #expect(snapshot.range(utf16Offsets: 1 ..< 2) == nil)
    #expect(snapshot.range(utf16Offsets: -1 ..< 0) == nil)
    #expect(snapshot.range(utf16Offsets: 0 ..< 8) == nil)
    #expect(snapshot.range(utf16Offsets: 7 ..< 7) == snapshot.range(10 ..< 10))
    #expect(snapshot.range(utf16Offsets: 4 ..< 5) == snapshot.range(6 ..< 8))
    #expect(snapshot.range(utf16Offsets: 5 ..< 7) == snapshot.range(8 ..< 10))
    #expect(SourceSnapshot(text: snapshot.text, language: .swift).utf16Offsets(for: emoji) == nil)
}

@Test func validBlockCommentReproducerRetainsKnownFalsePositive() throws {
    let snapshot = try fixture("block-comment")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    #expect(result.declarations.map(\.name) == ["A", "B"])
    #expect(!result.diagnostics.isEmpty)
    #expect(result.diagnostics.contains { $0.severity == .error })
    #expect(candidates(.init(name: .short("B")), in: result).count == 1)
    let ownLine = try TreeSitterSwiftExtractor().extract(from: fixture("block-comment-own-line"))
    #expect(ownLine.declarations.map(\.name) == ["A", "B"])
    #expect(ownLine.diagnostics.isEmpty)
}

@Test func incompleteSyntaxKeepsAvailableDeclarationsAndDiagnostics() throws {
    let snapshot = try fixture("incomplete")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    #expect(!result.diagnostics.isEmpty)
    #expect(candidates(.init(name: .short("Healthy")), in: result).count == 1)
    #expect(candidates(.init(name: .short("Tail")), in: result).count == 1)
    let broken = candidates(.init(name: .short("broken")), in: result)
    #expect(try #require(broken.first).signature == nil)
    #expect(result.diagnostics.compactMap { $0.range?.utf8Offsets } == [36 ..< 36, 90 ..< 91])
    #expect(candidates(.init(name: .short("broken()")), in: result).isEmpty)
    for diagnostic in result.diagnostics {
        #expect(diagnostic.severity == .error)
        let range = try #require(diagnostic.range)
        #expect(snapshot.text(in: range) != nil)
    }
}

@Test func missingTokensProduceDiagnosticsAlongsideMatches() throws {
    let snapshot = SourceSnapshot(text: "struct Open {", language: .swift)
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    #expect(result.diagnostics.contains { $0.message.hasPrefix("Tree-sitter: missing") })
    #expect(candidates(.init(name: .short("Open")), in: result).count == 1)
}

@Test func emptySourceAndEmbeddedNULAreNotTruncated() throws {
    let empty = try TreeSitterSwiftExtractor().extract(from: SourceSnapshot(text: "", language: .swift))
    #expect(empty.declarations.isEmpty)
    #expect(empty.diagnostics.isEmpty)
    let source = SourceSnapshot(text: "struct Before {}\u{0}\nstruct After {}", language: .swift)
    let result = try TreeSitterSwiftExtractor().extract(from: source)
    #expect(result.declarations.map(\.name) == ["Before", "After"])
    #expect(!result.diagnostics.isEmpty)
}

@Test func oneExtractorSupportsConcurrentIndependentSnapshots() async throws {
    let extractor = TreeSitterSwiftExtractor()
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0 ..< 12 {
            group.addTask {
                let name = "Type\(index)"
                let snapshot = SourceSnapshot(text: "struct \(name) {}", language: .swift)
                let result = try extractor.extract(from: snapshot)
                try expectSnapshotContract(result, from: snapshot)
                #expect(result.declarations.map(\.name) == [name])
            }
        }
        try await group.waitForAll()
    }
}

@Test func bindingInitializersAndEscapedExtensionsHaveCorrectScopes() throws {
    let snapshot = try fixture("scopes")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.qualifiedName) == [
        "Host", "Host.computed", "Host.computed.local", "Host.a", "Host.b", "Host.a.first", "Host.b.second",
        "Host.pair", "Host.pair.x", "Host.pair.y", "Host.Inner", "Host.Inner", "Host.Inner.f",
    ])
    #expect(candidates(.init(name: .qualified("Host.computed.local")), in: result).first?.kind == .variable)
    #expect(candidates(.init(name: .qualified("Host.b.second()")), in: result).first?.kind == .function)
    let scopes = candidates(.init(name: .qualified("Host.Inner")), in: result)
    #expect(scopes.map(\.kind) == [.type, .extensionScope])
    let extensionScope = try #require(scopes.last)
    #expect(snapshot.text(in: extensionScope.identifierRange) == "`Host` . `Inner`")
}

@Test func signatureBoundariesRetainTypeAnnotationsAndSuffixes() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("signature-boundaries"))
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.count == 6)
    #expect(candidates(.init(name: .short("implicitlyUnwrapped(_:)"), parameterTypes: ["Int!"]), in: result)
        .first?.signature?.returnType == "String!")
    #expect(candidates(.init(name: .short("callback()")), in: result).first?.signature?
        .returnType == "@Sendable () -> Void")
    #expect(candidates(.init(name: .short("nested(value:)"), parameterTypes: ["((Int, String) -> Bool)?"]), in: result)
        .first?.signature?.returnType == "(Int, String)")
    let constrained = try #require(candidates(.init(name: .short("constrained(value:)")), in: result).first?.signature)
    #expect(constrained.returnType == "T!")
    #expect(constrained.genericConstraints == "where T: AnyObject")
    #expect(candidates(
        .init(name: .short("ownership(_:other:)"), parameterTypes: ["borrowing Int", "consuming Int"]),
        in: result
    ).count == 1)
    #expect(candidates(.init(name: .short("spaced(value:)"), parameterTypes: ["[Int /* interior */]"]), in: result)
        .first?.signature?.returnType == "String")
}

@Test func aRecoveredBodyDoesNotEraseItsSoundCallableHeader() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("incomplete"))
    #expect(!result.diagnostics.isEmpty)
    let recovered = try #require(candidates(.init(name: .short("recovered(value:)")), in: result).first)
    #expect(recovered.signature?.parameters == [.init(name: "value", argumentLabel: "value", typeSyntax: "Int")])
}

@Test func wildcardPatternsDifferFromEscapedUnderscoreNames() throws {
    let snapshot = SourceSnapshot(text: "let _ = 1\nlet `_` = 2\nfunc `_`() {}", language: .swift)
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    #expect(result.declarations.map(\.name) == ["_", "_"])
    #expect(result.declarations.map { snapshot.text(in: $0.identifierRange) } == ["`_`", "`_`"])
    #expect(candidates(.init(name: .short("_()")), in: result).count == 1)
}

@Test func enumRawValueReferencesAreNotDeclarations() throws {
    // Not valid Swift semantically; extraction must still distinguish a name from a reference.
    let snapshot = SourceSnapshot(text: "enum Raw: Int { case one = value; case two = 2 }", language: .swift)
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    #expect(result.declarations.map(\.name) == ["Raw", "one", "two"])
    #expect(candidates(.init(name: .short("value")), in: result).isEmpty)
}

@Test func tupleLabelsAreNotDeclarations() throws {
    let snapshot = try fixture("tuple-bindings")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    let globals = result.declarations.filter { $0.enclosingScopes.isEmpty && $0.kind == .variable }
    #expect(globals.map(\.name) == ["a", "b", "repeat", "c"])
    #expect(globals.map { snapshot.text(in: $0.identifierRange) } == ["a", "b", "`repeat`", "c"])
    #expect(globals.prefix(2).allSatisfy {
        snapshot.text(in: $0.declarationRange) == "let (x: a, y: b) = (x: 1, y: 2)"
    })
    for label in ["x", "y", "outer", "inner", "ignored", "tail", "label"] {
        #expect(candidates(.init(name: .short(label)), in: result).isEmpty)
    }
}

@Test func tupleInitializerScopesDependOnPatternStructure() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("tuple-bindings"))
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.filter { !$0.enclosingScopes.isEmpty }.map(\.qualifiedName) == [
        "bindings().only", "bindings().temporary", "bindings().nested", "bindings().nestedTemporary",
        "bindings().labeled", "bindings().labeledTemporary", "bindings().single", "bindings().single.singleTemporary",
        "bindings().first", "bindings().second", "bindings().second.secondTemporary",
    ])
}

@Test(arguments: ["\n", "\r\n"])
func recoveredDeclarationRangesExcludeTrailingTrivia(newline: String) throws {
    let source = try fixture("incomplete-trivia").text.replacingOccurrences(of: "\n", with: newline)
    let snapshot = SourceSnapshot(text: source, language: .swift)
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    #expect(result.declarations.map(\.qualifiedName) == ["Open", "Open.value"])
    let valueText = "let value = 1"
    let outerText = "struct Open {" + newline + "    " + valueText
    #expect(result.declarations.map { snapshot.text(in: $0.declarationRange) } == [outerText, valueText])
    #expect(result.declarations.allSatisfy { $0.declarationRange.utf8Offsets.upperBound == outerText.utf8.count })
    #expect(!result.diagnostics.isEmpty)
    #expect(result.diagnostics.allSatisfy { $0.message == "Tree-sitter: missing }" })
    #expect(result.diagnostics.allSatisfy {
        $0.range?.utf8Offsets == snapshot.text.utf8.count ..< snapshot.text.utf8.count
    })
}

@Test func swiftParameterMetadataSeparatesBindingsLabelsAndDefaults() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("parameter-metadata"))
    #expect(result.diagnostics.isEmpty)
    let labels = try #require(candidates(.init(name: .short("labels(value:_:discarded:)")), in: result).first)
    #expect(labels.signature?.parameters == [
        .init(name: "local", argumentLabel: "value", typeSyntax: "Int"),
        .init(name: "hidden", typeSyntax: "String"),
        .init(argumentLabel: "discarded", typeSyntax: "Bool"),
    ])
    let defaults = try #require(candidates(.init(name: .short("defaults(value:done:)")), in: result).first)
    #expect(defaults.signature?.parameters == [
        .init(name: "value", argumentLabel: "value", typeSyntax: "Int", hasDefaultValue: true),
        .init(name: "done", argumentLabel: "done", typeSyntax: "() -> Void", hasDefaultValue: true),
    ])
    let escaped = try #require(candidates(.init(name: .short("escaped(repeat:)")), in: result).first)
    #expect(escaped.signature?.parameters == [.init(name: "for", argumentLabel: "repeat", typeSyntax: "Int")])
    let pack = try #require(candidates(.init(name: .short("pack(_:)")), in: result).first)
    #expect(pack.signature?.parameters == [
        .init(name: "values", typeSyntax: "repeat each T", passing: .variadicPositional),
    ])
    let callables = try TreeSitterSwiftExtractor().extract(from: fixture("callables"))
    let variadic = try #require(candidates(.init(name: .short("gather(values:)")), in: callables).first)
    #expect(variadic.signature?.parameters == [
        .init(name: "values", argumentLabel: "values", typeSyntax: "Int...", passing: .variadicPositional),
    ])
    let operation = try #require(candidates(.init(name: .qualified("Number.+(_:_:)")), in: callables).first)
    #expect(operation.signature?.parameters.map(\.name) == ["lhs", "rhs"])
    #expect(operation.signature?.parameters.allSatisfy { $0.argumentLabel == nil } == true)
}
