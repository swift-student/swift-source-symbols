import Foundation
import SourceSymbols
import Testing

@Test func associatedValueLabelsAndTypeTriviaComeFromDirectSyntaxChildren() throws {
    let snapshot = try fixture("enum-associated-labels")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.qualifiedName) == [
        "Labels",
        "Labels.explicit",
        "Labels.escaped",
        "Labels.annotated",
    ])
    let explicit = try #require(candidates(.init(name: .qualified("Labels.explicit(_:)")), in: result).first)
    #expect(explicit.signature == CallableSignature(parameters: [.init(typeSyntax: "Int")]))
    let escaped = try #require(candidates(.init(name: .qualified("Labels.escaped(_:)")), in: result).first)
    #expect(escaped.signature == CallableSignature(parameters: [.init(argumentLabel: "_", typeSyntax: "String")]))
    let annotated = try #require(candidates(.init(name: .qualified("Labels.annotated(callback:value:)")), in: result)
        .first)
    #expect(annotated.signature == CallableSignature(parameters: [
        .init(argumentLabel: "callback", typeSyntax: "@Sendable (Int, String) -> Void"),
        .init(argumentLabel: "value", typeSyntax: "[Int /* interior */]", hasDefaultValue: true),
    ]))
}

@Test func underscoreOnlyAssociatedValueLabelRetainsKnownGrammarDiagnostic() throws {
    let snapshot = try fixture("enum-underscore-label")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.qualifiedName) == ["Example", "Example.value"])
    #expect(result.diagnostics.map { $0.range?.utf8Offsets } == [27 ..< 27])
    #expect(result.diagnostics.allSatisfy { $0.severity == .error })
    let value = try #require(candidates(.init(name: .qualified("Example.value")), in: result).first)
    #expect(value.signature == nil)
    #expect(value.identifierRange.utf8Offsets == 20 ..< 25)
    #expect(snapshot.text(in: value.declarationRange) == "case value(_: Int)")
    expectMatches(.init(name: .qualified("Example.value(_:)")), in: result, identifierOffsets: [])
}

@Test func associatedValuesHaveSignaturesWithoutInventedBindings() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("enum-associated-values"))
    #expect(result.diagnostics.isEmpty)
    let expected: [(String, [CallableSignature.Parameter])] = [
        ("payload(value:)", [.init(argumentLabel: "value", typeSyntax: "Int")]),
        ("raw(_:)", [.init(typeSyntax: "Int")]),
        ("mixed(_:label:_:)", [.init(typeSyntax: "Int"),
                               .init(argumentLabel: "label", typeSyntax: "[String: (Int, String)]"),
                               .init(typeSyntax: "Bool")]),
        ("repeat(for:callback:)", [.init(argumentLabel: "for", typeSyntax: "Int", hasDefaultValue: true),
                                   .init(argumentLabel: "callback", typeSyntax: "(Int, String) -> Void",
                                         hasDefaultValue: true)]),
        ("café(😀:)", [.init(argumentLabel: "😀", typeSyntax: "String")]),
        ("é(_:)", [.init(typeSyntax: "Int")]),
    ]
    for (name, parameters) in expected {
        let declaration = try #require(candidates(.init(name: .qualified("Event." + name)), in: result).first)
        #expect(declaration.kind == .enumCase)
        #expect(declaration.signature == CallableSignature(parameters: parameters))
    }
    for query in [DeclarationQuery.Name.short("payload"), .short("payload(value:)"),
                  .qualified("Event.payload"), .qualified("Event.payload(value:)")]
    {
        expectMatches(.init(name: query), in: result, identifierOffsets: [29 ..< 36])
    }
    for name in ["Event.ready", "Raw.one", "Raw.two"] {
        let declaration = try #require(candidates(.init(name: .qualified(name)), in: result).first)
        #expect(declaration.signature == nil)
        #expect(declaration.callableName == nil)
        #expect(declaration.qualifiedCallableName == nil)
        expectMatches(.init(name: .qualified(name + "()")), in: result, identifierOffsets: [])
        expectMatches(.init(name: .qualified(name), parameterTypes: []), in: result, identifierOffsets: [])
    }
    expectMatches(.init(name: .qualified("Event.choice")), in: result,
                  identifierOffsets: [238 ..< 244, 258 ..< 264, 280 ..< 286])
    expectMatches(.init(name: .qualified("Event.choice(value:)")), in: result,
                  identifierOffsets: [238 ..< 244, 280 ..< 286])
    expectMatches(.init(name: .short("choice(text:)")), in: result, identifierOffsets: [258 ..< 264])
    expectMatches(.init(name: .qualified("Event.choice(value:)"), parameterTypes: ["String"]), in: result,
                  identifierOffsets: [280 ..< 286])
    expectMatches(.init(name: .short("choice"), signature: CallableSignature(parameters: [
        .init(argumentLabel: "value", typeSyntax: "Int"),
    ])), in: result, identifierOffsets: [238 ..< 244])
}

@Test func enclosingCallableLabelsDistinguishOnlyDistinctLabelOverloads() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("callable-scopes"))
    #expect(result.diagnostics.isEmpty)
    expectMatches(.init(name: .qualified("Host.outer")), in: result,
                  identifierOffsets: [23 ..< 28, 332 ..< 337, 381 ..< 386])
    expectMatches(.init(name: .qualified("Host.outer(value:).inner()")), in: result,
                  identifierOffsets: [56 ..< 61, 409 ..< 414])
    expectMatches(.init(name: .qualified("Host.outer(value:).inner")), in: result,
                  identifierOffsets: [56 ..< 61, 409 ..< 414])
    expectMatches(.init(name: .qualified("Host.outer(text:).inner()")), in: result, identifierOffsets: [359 ..< 364])
    expectMatches(.init(name: .short("inner()")), in: result,
                  identifierOffsets: [56 ..< 61, 359 ..< 364, 409 ..< 414])
    // Filters describe the queried declaration, never the enclosing callable's parameters.
    expectMatches(.init(name: .qualified("Host.outer(value:).inner()"), parameterTypes: []), in: result,
                  identifierOffsets: [56 ..< 61, 409 ..< 414])
    expectMatches(.init(name: .qualified("Host.outer(value:).inner()"), parameterTypes: ["Int"]), in: result,
                  identifierOffsets: [])
    expectMatches(.init(name: .qualified("Host.outer.inner()")), in: result, identifierOffsets: [])
    expectMatches(.init(name: .qualified("Host.outer(value:).middle(_:).leaf(flag:)")), in: result,
                  identifierOffsets: [146 ..< 150])
    expectMatches(.init(name: .qualified("Host.outer(value:).Nested.member().body")), in: result,
                  identifierOffsets: [232 ..< 236])
    expectMatches(.init(name: .qualified("Host.outer(value:).closure.captured")), in: result,
                  identifierOffsets: [281 ..< 289])
    expectMatches(.init(name: .qualified("Host.init(seed:).local")), in: result, identifierOffsets: [448 ..< 453])
    expectMatches(.init(name: .qualified("Host.subscript(key:).local")), in: result, identifierOffsets: [506 ..< 511])
    expectMatches(.init(name: .qualified("Lifetime.deinit().local")), in: result, identifierOffsets: [669 ..< 674])
    expectMatches(.init(name: .qualified("anonymous().repeated")), in: result,
                  identifierOffsets: [720 ..< 728, 754 ..< 762])
}

@Test func parametersRemainMetadataRatherThanNavigableDeclarations() throws {
    let result = try TreeSitterSwiftExtractor().extract(from: fixture("callable-scopes"))
    for name in ["value", "text", "input", "flag", "seed", "key", "index", "for", "😀"] {
        expectMatches(.init(name: .short(name)), in: result, identifierOffsets: [])
    }
    for name in ["Host.outer(value:).value", "Host.outer(text:).text", "Host.init(seed:).seed",
                 "Host.subscript(key:).index", "Host.repeat(for:).input", "Host.repeat(for:).café(😀:).😀"]
    {
        expectMatches(.init(name: .qualified(name)), in: result, identifierOffsets: [])
    }
    let outer = try #require(candidates(.init(name: .qualified("Host.outer(value:)"), parameterTypes: ["Int"]),
                                        in: result).first)
    #expect(outer.signature?.parameters == [.init(name: "value", argumentLabel: "value", typeSyntax: "Int")])
    expectMatches(.init(name: .qualified("Host.outer(value:).local")), in: result, identifierOffsets: [79 ..< 84])
}

@Test(arguments: ["\n", "\r\n"])
func swiftLookupAliasesPreserveUnicodeAndLineEndingRanges(newline: String) throws {
    let examples: [(String, String, Range<Int>, Range<Int>, String, String)] = [
        ("enum-associated-values", "Event.café(😀:)", 199 ..< 204, 194 ..< 228, "café", "case café(😀: String), é(Int)"),
        ("enum-associated-values", "Event.repeat(for:callback:)", 118 ..< 126, 113 ..< 189, "`repeat`",
         "case `repeat`(`for`: Int = 1, callback: (Int, String) -> Void = { _, _ in })"),
        ("callable-scopes", "Host.repeat(for:).café(😀:).é", 621 ..< 624, 617 ..< 628, "é", "let é = 1"),
    ]
    for (fixtureName, query, identifier, full, identifierText, fullText) in examples {
        let original = try fixture(fixtureName).text
        let snapshot = SourceSnapshot(text: original.replacingOccurrences(of: "\n", with: newline), language: .swift)
        let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
        try expectSnapshotContract(result, from: snapshot)
        #expect(result.diagnostics.isEmpty)
        /// The literal LF offsets above are source-authored; CRLF adds one byte per preceding LF.
        func offset(_ value: Int) -> Int {
            value + (newline == "\r\n" ? original.utf8.prefix(value).filter { $0 == 10 }.count : 0)
        }
        let expectedIdentifier = offset(identifier.lowerBound) ..< offset(identifier.upperBound)
        expectMatches(.init(name: .qualified(query)), in: result, identifierOffsets: [expectedIdentifier])
        let declaration = try #require(candidates(.init(name: .qualified(query)), in: result).first)
        #expect(declaration.declarationRange.utf8Offsets == offset(full.lowerBound) ..< offset(full.upperBound))
        #expect(snapshot.text(in: declaration.identifierRange) == identifierText)
        #expect(snapshot.text(in: declaration.declarationRange) == fullText)
    }
}

@Test func damagedLookupHeadersRetainBaseNamesAndHealthySiblingSignatures() throws {
    let snapshot = try fixture("lookup-recovery")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(!result.diagnostics.isEmpty)
    let broken = try #require(candidates(.init(name: .qualified("Recovered.broken")), in: result).first)
    #expect(broken.signature == nil)
    #expect(broken.callableName == nil)
    expectMatches(.init(name: .qualified("Recovered.broken(value:)")), in: result, identifierOffsets: [])
    expectMatches(.init(name: .qualified("Recovered.good(value:)")), in: result, identifierOffsets: [26 ..< 30])
    expectMatches(.init(name: .qualified("Recovered.tail(_:)")), in: result, identifierOffsets: [61 ..< 65])
    let damaged = try #require(candidates(.init(name: .qualified("Recovery.damaged")), in: result).first)
    #expect(damaged.signature == nil)
    #expect(damaged.callableName == nil)
    expectMatches(.init(name: .qualified("Recovery.damaged.inner()")), in: result, identifierOffsets: [127 ..< 132])
    expectMatches(.init(name: .qualified("Recovery.body(value:).nested()")), in: result,
                  identifierOffsets: [181 ..< 187])
}
