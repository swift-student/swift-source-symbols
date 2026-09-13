import SourceSymbolsCore
import Testing

/// Hand-constructed model cases exercise the core without claiming another parser is available.
private func declaration(_ qualifiedName: String, signature: CallableSignature?,
                         callableName: String? = nil, qualifiedCallableName: String? = nil) throws -> Declaration
{
    let snapshot = SourceSnapshot(text: "send", language: .swift)
    let range = try #require(snapshot.range(0 ..< 4))
    return try Declaration(name: "send", qualifiedName: qualifiedName, kind: .method,
                           signature: signature, callableName: callableName,
                           qualifiedCallableName: qualifiedCallableName,
                           identifierRange: range, declarationRange: range)
}

@Test func lookupSpellingsBelongToTheBackend() throws {
    let signature = CallableSignature(parameters: [
        .init(name: "payload"),
        .init(name: "timeout", argumentLabel: "timeout", passing: .keyword, hasDefaultValue: true),
    ])
    let symbol = try declaration("Client#send", signature: signature,
                                 callableName: "send(payload, timeout:)",
                                 qualifiedCallableName: "Client#send(payload, timeout:)")
    for name in ["Client#send", "Client#send(payload, timeout:)"] {
        if case let .unique(found) = DeclarationMatcher.match(.init(name: .qualified(name)), in: [symbol]) {
            #expect(found.qualifiedName == "Client#send")
        } else {
            Issue.record("Expected the backend's exact qualified spelling")
        }
    }
    if case .missing = DeclarationMatcher.match(.init(name: .short("send(_:timeout:)")), in: [symbol]) {
        // Swift-style labels must not be synthesized for another backend's metadata.
    } else {
        Issue.record("The core invented a callable spelling")
    }
    let withoutAliases = try declaration("Client#send", signature: signature)
    #expect(withoutAliases.callableName == nil)
    #expect(withoutAliases.qualifiedCallableName == nil)
}

@Test func annotationFiltersDistinguishAbsentTypesUnknownSignaturesAndZeroArity() throws {
    let symbols = try [
        declaration("untyped", signature: .init(parameters: [.init(name: "value")])),
        declaration("typed", signature: .init(parameters: [.init(name: "value", typeSyntax: "Int")])),
        declaration("zero", signature: .init(parameters: [])),
        declaration("unknown", signature: nil),
    ]
    let queries: [([String?], String)] = [([nil], "untyped"), (["Int"], "typed"), ([], "zero")]
    for (types, expectedName) in queries {
        if case let .unique(found) = DeclarationMatcher.match(
            .init(name: .short("send"), parameterTypes: types), in: symbols
        ) {
            #expect(found.qualifiedName == expectedName)
        } else {
            Issue.record("Expected only \(expectedName) for annotation filter \(types)")
        }
    }
    if case let .ambiguous(found) = DeclarationMatcher.match(.init(name: .short("send")), in: symbols) {
        #expect(found.map(\.qualifiedName) == ["untyped", "typed", "zero", "unknown"])
    } else {
        Issue.record("An omitted annotation filter must preserve every candidate")
    }
}

@Test func exactSignaturesDistinguishPassingDefaultsAndBindingNames() throws {
    let parameters: [CallableSignature.Parameter] = [
        .init(name: "value"),
        .init(name: "value", argumentLabel: "value", passing: .keyword),
        .init(name: "value", argumentLabel: "value", passing: .keyword, hasDefaultValue: true),
        .init(name: "items", passing: .variadicPositional),
        .init(name: "options", passing: .variadicKeyword),
        .init(name: "callback", passing: .block),
        .init(name: "renamed"),
    ]
    let symbols = try parameters.enumerated().map { index, parameter in
        try declaration("candidate\(index)", signature: .init(parameters: [parameter]))
    }
    for (index, parameter) in parameters.enumerated() {
        if case let .unique(found) = DeclarationMatcher.match(
            .init(name: .short("send"), parameterTypes: [nil], signature: .init(parameters: [parameter])), in: symbols
        ) {
            #expect(found.qualifiedName == "candidate\(index)")
        } else {
            Issue.record("Exact metadata must select candidate \(index)")
        }
    }
    if case let .ambiguous(found) = DeclarationMatcher.match(
        .init(name: .short("send"), parameterTypes: [nil]), in: symbols
    ) {
        #expect(found.map(\.qualifiedName) == (0 ..< parameters.count).map { "candidate\($0)" })
    } else {
        Issue.record("Absent annotations alone cannot distinguish these callables")
    }
    if case .missing = DeclarationMatcher.match(
        .init(name: .short("send"), parameterTypes: ["Int"], signature: symbols[0].signature), in: symbols
    ) {
        // A signature match does not override a conflicting annotation filter.
    } else {
        Issue.record("Both filters must apply")
    }
}
