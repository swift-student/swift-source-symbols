import SourceSymbolsCore
import Testing

@Test func unicodeRangesAndSnapshotIdentity() throws {
    let source = SourceSnapshot(text: "a😀e\u{301}\r\n", language: .swift)
    #expect(source.range(-1 ..< 0) == nil)
    #expect(source.range(0 ..< 100) == nil)
    #expect(source.range(2 ..< 5) == nil)
    let emoji = try #require(source.range(1 ..< 5))
    #expect(source.text(in: emoji) == "😀")
    #expect(try source.text(in: #require(source.range(6 ..< 8))) == "\u{301}")
    #expect(try source.text(in: #require(source.range(8 ..< 10))) == "\r\n")
    #expect(source.range(10 ..< 10) != nil)
    #expect(SourceSnapshot(text: source.text, language: .swift).text(in: emoji) == nil)
}

@Test func matchingPreservesOverloadsAndScopes() throws {
    let source = SourceSnapshot(text: "run", language: .swift)
    let range = try #require(source.range(0 ..< 3))
    let declarations = try [
        ("A", []),
        ("A", [CallableSignature.Parameter(argumentLabel: "value", typeSyntax: "Int")]),
        ("B", []),
    ].map { scope, parameters in
        let callableName = parameters.isEmpty ? "run()" : "run(value:)"
        return try Declaration(name: "run", qualifiedName: scope + ".run", kind: .method,
                               signature: .init(parameters: parameters), callableName: callableName,
                               qualifiedCallableName: scope + "." + callableName,
                               enclosingScopes: [scope], identifierRange: range,
                               declarationRange: range)
    }
    if case let .ambiguous(candidates) = DeclarationMatcher.match(.init(name: .short("run")), in: declarations) {
        #expect(candidates.count == 3)
    } else {
        Issue.record("Expected all overloads")
    }
    if case let .ambiguous(candidates) = DeclarationMatcher.match(.init(name: .qualified("A.run")), in: declarations) {
        #expect(candidates.count == 2)
    } else {
        Issue.record("Expected scoped overloads")
    }
    if case let .unique(found) = DeclarationMatcher.match(
        .init(name: .qualified("A.run(value:)")), in: declarations
    ) {
        #expect(found.signature?.parameters == [.init(argumentLabel: "value", typeSyntax: "Int")])
    } else {
        Issue.record("Expected exact signature")
    }
    if case .missing = DeclarationMatcher.match(.init(name: .short("missing")), in: declarations) {
        // Expected.
    } else {
        Issue.record("Expected missing")
    }
}

@Test func rejectsMixedSnapshotsAndOutOfBoundsIdentifiers() throws {
    let source = SourceSnapshot(text: "abc", language: .swift)
    let other = SourceSnapshot(text: "abc", language: .swift)
    let full = try #require(source.range(0 ..< 3))
    let foreign = try #require(other.range(0 ..< 3))
    #expect(throws: ExtractionError.self) {
        try Declaration(name: "abc", qualifiedName: "abc", kind: .type,
                        identifierRange: foreign, declarationRange: full)
    }
    let partial = try #require(source.range(0 ..< 1))
    #expect(throws: ExtractionError.self) {
        try Declaration(name: "abc", qualifiedName: "abc", kind: .type,
                        identifierRange: full, declarationRange: partial)
    }
    #expect(throws: ExtractionError.self) {
        try ExtractionResult(snapshot: source, declarations: [], diagnostics: [
            ParseDiagnostic(severity: .error, message: "Recovered syntax", range: foreign),
        ])
    }
}

@Test func recoveryKeepsDiagnosticsAlongsideMatches() throws {
    let source = SourceSnapshot(text: "abc", language: .swift)
    let range = try #require(source.range(0 ..< 3))
    let declaration = try Declaration(name: "abc", qualifiedName: "abc", kind: .type,
                                      identifierRange: range, declarationRange: range)
    let result = try ExtractionResult(snapshot: source, declarations: [declaration], diagnostics: [
        ParseDiagnostic(severity: .error, message: "Incomplete declaration", range: range),
    ])
    #expect(result.declarations.count == 1)
    #expect(result.diagnostics.count == 1)
}
