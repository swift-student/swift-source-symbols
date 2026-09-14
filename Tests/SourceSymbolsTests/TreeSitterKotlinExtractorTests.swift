import Foundation
import SourceSymbols
import Testing

private func kotlinFixture(_ name: String) throws -> SourceSnapshot {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "kt", subdirectory: "Fixtures/Kotlin"))
    return try SourceSnapshot(text: String(contentsOf: url, encoding: .utf8), language: .kotlin)
}

private struct KotlinExpectedFixture: Decodable {
    let declarations: [ExpectedDeclaration]
    let diagnosticRanges: [[Int]]
    let qualifiedNames: [String]
}

private func kotlinCandidates(_ name: String, in result: ExtractionResult) -> [Declaration] {
    result.declarations.filter { $0.name == name }
}

@Test(arguments: ["declarations", "unicode-lf", "unicode-crlf", "recovery", "incomplete"])
func kotlinDeclarationCorpus(name: String) throws {
    let snapshot = try kotlinFixture(name)
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Kotlin"))
    let expected = try JSONDecoder().decode(KotlinExpectedFixture.self, from: Data(contentsOf: url))
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    try expectBackendContract(result, from: snapshot, declarations: expected.declarations,
                              diagnosticRanges: expected.diagnosticRanges.map { $0[0] ..< $0[1] })
    #expect(result.declarations.map(\.qualifiedName) == expected.qualifiedNames)
}

@Test func kotlinOverloadsAndRepeatedLocalNamesRemainAmbiguous() throws {
    let result = try TreeSitterKotlinExtractor().extract(from: kotlinFixture("declarations"))
    let overloads = kotlinCandidates("add", in: result)
    #expect(overloads.count == 2)
    expectMatches(.init(name: .qualified("shop.Cart.add")), in: result,
                  identifierOffsets: overloads.map(\.identifierRange.utf8Offsets))
    try expectMatches(.init(name: .short("add"), parameterTypes: ["Int"]), in: result,
                      identifierOffsets: [#require(overloads.first).identifierRange.utf8Offsets])
    let second = try #require(overloads.last)
    expectMatches(.init(name: .qualified("shop.Cart.add"), signature: second.signature), in: result,
                  identifierOffsets: [second.identifierRange.utf8Offsets])
    expectMatches(.init(name: .short("Add")), in: result, identifierOffsets: [])
    expectMatches(.init(name: .short("add"), parameterTypes: [nil]), in: result, identifierOffsets: [])
    expectMatches(.init(name: .short("add(value:)")), in: result, identifierOffsets: [])
    #expect(result.declarations.allSatisfy { $0.callableName == nil && $0.qualifiedCallableName == nil })

    let scopes = try TreeSitterKotlinExtractor().extract(from: kotlinFixture("scopes"))
    expectMatches(.init(name: .qualified("demo.when.outer.local")), in: scopes,
                  identifierOffsets: [78 ..< 83, 122 ..< 127])
}

@Test func kotlinParametersRetainTypesDefaultsGenericsAndSuspend() throws {
    let snapshot = try kotlinFixture("parameters")
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
    let choose = try #require(kotlinCandidates("choose", in: result).first)
    #expect(choose.qualifiedName == "sample.List<T>.choose")
    #expect(choose.signature == CallableSignature(parameters: [
        .init(name: "value", argumentLabel: "value", typeSyntax: "T"),
        .init(name: "others", argumentLabel: "others", typeSyntax: "T", passing: .variadicPositional),
        .init(name: "callback", argumentLabel: "callback", typeSyntax: "(T) -> Unit", hasDefaultValue: true),
        .init(name: "when", argumentLabel: "when", typeSyntax: "Map<String, List<T?>>", hasDefaultValue: true),
    ], genericParameters: "<T>", effects: ["suspend"], returnType: "T?", genericConstraints: "where T : Any"))
    let render = kotlinCandidates("render", in: result)
    #expect(render.map(\.qualifiedName) == ["sample.String.render", "sample.Int.render"])
    expectMatches(.init(name: .short("render"), parameterTypes: ["Int"]), in: result,
                  identifierOffsets: render.map(\.identifierRange.utf8Offsets))
    expectMatches(.init(name: .qualified("sample.String.render"), parameterTypes: ["Int"]), in: result,
                  identifierOffsets: [259 ..< 265])
    #expect(kotlinCandidates("plain", in: result).first?.signature == .init(parameters: []))
    #expect(kotlinCandidates("Empty", in: result).first?.signature == .init(parameters: []))
    #expect(kotlinCandidates("Implicit", in: result).first?.signature == nil)
    #expect(kotlinCandidates("WithDefaults", in: result).first?.signature?.parameters == [
        .init(name: "title", argumentLabel: "title", typeSyntax: "String", hasDefaultValue: true),
        .init(name: "flags", argumentLabel: "flags", typeSyntax: "Int", passing: .variadicPositional),
    ])
    #expect(kotlinCandidates("size", in: result).first?.qualifiedName == "sample.String.size")
    #expect(kotlinCandidates("flags", in: result).isEmpty)
}

@Test func kotlinLexicalScopesAndKindsStayIndependentOfReceiverPaths() throws {
    let snapshot = try kotlinFixture("scopes")
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.qualifiedName) == [
        "demo.when.outer", "demo.when.outer.local", "demo.when.outer.local", "demo.when.outer.Inner",
        "demo.when.outer.Inner.member", "demo.when.outer.Inner.member.nested", "demo.when.outer.owned",
        "demo.when.outer.owned.helper", "demo.when.outer.left", "demo.when.outer.right", "demo.when.outer.shared",
        "demo.when.service", "demo.when.service.work", "demo.when.service.work.local", "demo.when.Host",
        "demo.when.Host.Factory", "demo.when.Host.Factory.make", "demo.when.Host.value",
        "demo.when.Host.value.adjusted",
        "demo.when.Host.String.extension", "demo.when.Host.String.extension.nested",
    ])
    #expect(result.declarations.map(\.kind) == [
        .function, .function, .function, .type, .method, .variable, .variable, .function, .variable, .variable,
        .function, .property, .method, .variable, .type, .type, .method, .property, .variable, .method, .function,
    ])
    #expect(kotlinCandidates("nested", in: result).last?.enclosingScopes == ["Host", "extension"])
    let left = try #require(kotlinCandidates("left", in: result).first)
    let right = try #require(kotlinCandidates("right", in: result).first)
    #expect(left.declarationRange == right.declarationRange)
    #expect(left.headerRange == right.headerRange)
}

@Test func kotlinHeadersUseSyntaxBoundariesAndPreserveTrivia() throws {
    let snapshot = try kotlinFixture("trivia")
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.name) == ["Host", "callback", "work", "stored", "delegated", "computed", "Alias"])
    let headers = result.declarations.map { $0.headerRange.flatMap(snapshot.text(in:)) }
    #expect(headers == [
        "@Mark(\"{ fun fake() {} }\")\npublic class Host(val callback: () -> Unit = { println(\"}\") })",
        "val callback: () -> Unit = { println(\"}\") }",
        "suspend fun <T> work(\n        value: List</* inside */ T?>,\n        callback: () -> Unit = { println(\"{\") },\n    ): T? where T : Any",
        "val stored = { \"fun fake() {}\" }",
        "val delegated by lazy { 1 }",
        "val computed: Int",
        "typealias Alias = Map<String, Int>",
    ])
    #expect(kotlinCandidates("work", in: result).first?.signature?.parameters.map(\.typeSyntax) == [
        "List</* inside */ T?>", "() -> Unit",
    ])
    let computed = try #require(kotlinCandidates("computed", in: result).first)
    #expect(snapshot.text(in: computed.declarationRange) == "val computed: Int /* before getter */\n        get() = 1")

    let declarations = try TreeSitterKotlinExtractor().extract(from: kotlinFixture("declarations"))
    let constructor = try #require(kotlinCandidates("constructor", in: declarations).first)
    #expect(constructor.signature?.parameters == [.init(name: "item", argumentLabel: "item", typeSyntax: "T")])
    #expect(constructor.headerRange.flatMap(declarations.snapshot.text(in:)) == "constructor(item: T) : this(item, 1)")
    let companion = try #require(kotlinCandidates("Companion", in: declarations).first)
    #expect(declarations.snapshot.text(in: companion.identifierRange) == "object")
}

@Test func kotlinDamagedHeadersDifferFromRecoveredBodies() throws {
    let snapshot = try kotlinFixture("recovery")
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    let body = try #require(kotlinCandidates("bodyError", in: result).first)
    #expect(body.signature?.parameters == [.init(name: "value", argumentLabel: "value", typeSyntax: "Int")])
    #expect(body.headerRange.flatMap(snapshot.text(in:)) == "fun bodyError(value: Int)")
    let header = try #require(kotlinCandidates("headerError", in: result).first)
    #expect(header.signature == nil && header.headerRange == nil)
    expectMatches(.init(name: .short("headerError"), parameterTypes: []), in: result, identifierOffsets: [])
    #expect(!result.diagnostics.isEmpty)
}

@Test(arguments: ["unicode-lf", "unicode-crlf"])
func kotlinUnicodeRangesAndPositionsRemainSnapshotBound(name: String) throws {
    let snapshot = try kotlinFixture(name)
    #expect(snapshot.text.utf8.contains(13) == (name == "unicode-crlf"))
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    let method = try #require(kotlinCandidates("café", in: result).first)
    #expect(snapshot.text(in: method.identifierRange)?.utf8.elementsEqual("`café`".utf8) == true)
    #expect(method.signature?.parameters == [
        .init(name: "clé", argumentLabel: "clé", typeSyntax: "String", hasDefaultValue: true),
    ])
    let position = SourcePositionIndex(snapshot: snapshot).position(in: method.identifierRange, columnEncoding: .utf16)
    #expect(position?.line == 4 && position?.column == 9)
    let other = SourceSnapshot(text: snapshot.text, language: .kotlin)
    #expect(other.text(in: method.identifierRange) == nil)
    let header = try #require(method.headerRange)
    #expect(other.text(in: header) == nil)
}

@Test func kotlinAndOtherBackendsRejectUnsupportedLanguages() throws {
    for language in [SourceLanguage.swift, .ruby] {
        #expect(throws: ExtractionError.self) {
            try TreeSitterKotlinExtractor().extract(from: SourceSnapshot(text: "", language: language))
        }
    }
    for extractor: any DeclarationExtractor in [TreeSitterSwiftExtractor(), TreeSitterRubyExtractor()] {
        #expect(throws: ExtractionError.self) {
            try extractor.extract(from: SourceSnapshot(text: "", language: .kotlin))
        }
    }
}

@Test func kotlinEmptyInputAndEmbeddedNULPreserveTheSnapshotAndDiagnostics() throws {
    let empty = try TreeSitterKotlinExtractor().extract(from: SourceSnapshot(text: "", language: .kotlin))
    #expect(empty.declarations.isEmpty && empty.diagnostics.isEmpty)
    let snapshot = SourceSnapshot(text: "fun before() {}\n\0\nfun after() {}\n", language: .kotlin)
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    // This grammar recovers everything after NUL as one ERROR, through the actual EOF.
    #expect(result.declarations.map(\.name) == ["before"])
    #expect(result.diagnostics.map { $0.range?.utf8Offsets } == [15 ..< 33])
    try expectSnapshotContract(result, from: snapshot)
}

@Test func kotlinExtractorCanBeReusedConcurrently() async throws {
    let extractor = TreeSitterKotlinExtractor()
    let snapshot = try kotlinFixture("declarations")
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0 ..< 16 {
            group.addTask {
                let result = try extractor.extract(from: snapshot)
                #expect(result.diagnostics.isEmpty)
                #expect(result.declarations.count == 27)
                try expectSnapshotContract(result, from: snapshot)
            }
        }
        try await group.waitForAll()
    }
}

@Test func kotlinSyntaxIncludesEnumBodiesAndIgnoresCommentsStringsAndReferences() throws {
    let snapshot = try kotlinFixture("syntax")
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.qualifiedName) == [
        "syntax.Mark", "syntax.Mark.value", "syntax.Identifier", "syntax.Identifier.raw", "syntax.Shape",
        "syntax.Action", "syntax.Action.invoke", "syntax.Mode", "syntax.Mode.code", "syntax.Mode.FIRST",
        "syntax.Mode.FIRST.label", "syntax.Mode.SECOND", "syntax.Mode.label", "syntax.Registry", "syntax.Registry.ID",
        "syntax.Registry.multiline", "syntax.Registry.get", "syntax.Registry.accepts", "syntax.defaults",
        "syntax.defaults.nested", "syntax.repeat", "syntax.repeat",
    ])
    let first = try #require(kotlinCandidates("FIRST", in: result).first)
    #expect(first.kind == .enumCase)
    #expect(first.headerRange.flatMap(snapshot.text(in:)) == "FIRST(1)")
    let repeated = kotlinCandidates("repeat", in: result)
    #expect(repeated.count == 2)
    expectMatches(.init(name: .qualified("syntax.repeat"), parameterTypes: ["Int"]), in: result,
                  identifierOffsets: repeated.map(\.identifierRange.utf8Offsets))
    #expect(kotlinCandidates("get", in: result).first?.signature?.parameters == [
        .init(name: "index", argumentLabel: "index", typeSyntax: "Int"),
    ])
}

@Test func kotlinHiddenRecoveryDiagnosticsDoNotDiscardSoundHeaders() throws {
    let snapshot = try kotlinFixture("compact")
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.qualifiedName) == ["Compact", "Compact.run"])
    #expect(result.diagnostics.map { $0.range?.utf8Offsets } == [14 ..< 30])
    #expect(result.diagnostics.allSatisfy { $0.severity == .error })
    #expect(result.declarations.map { $0.headerRange.flatMap(snapshot.text(in:)) } == ["class Compact", "fun run()"])
}

@Test func kotlinDamagedDefaultsDoNotInventCompleteSignatures() throws {
    let snapshot = try kotlinFixture("damaged-default")
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.name) == ["damaged", "after"])
    let damaged = try #require(result.declarations.first)
    #expect(damaged.signature == nil && damaged.headerRange == nil)
    #expect(result.diagnostics.map { $0.range?.utf8Offsets } == [23 ..< 24])
}

@Test func kotlinReceiverModifiersDistinguishQualifiedFunctionsAndProperties() throws {
    let snapshot = try kotlinFixture("receiver-modifiers")
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.qualifiedName) == [
        "receivers.suspend(()->Unit).run", "receivers.(()->Unit).run", "receivers.suspend(()->Unit).run",
        "receivers.@receiver:Mark(String).annotated", "receivers.suspend(()->Unit).ready", "receivers.(()->Unit).ready",
    ])
    let runs = kotlinCandidates("run", in: result)
    #expect(runs.allSatisfy { $0.signature?.effects == [] })
    #expect(runs.map { $0.signature?.parameters.map(\.typeSyntax) } == [[], [], ["Int"]])
    #expect(runs.first?.headerRange.flatMap(snapshot.text(in:)) == "fun suspend /* receiver */ (() -> Unit).run()")
    expectMatches(.init(name: .qualified("receivers.suspend(()->Unit).run")), in: result,
                  identifierOffsets: [59 ..< 62, 121 ..< 124])
    expectMatches(.init(name: .qualified("receivers.suspend(()->Unit).run"), parameterTypes: []), in: result,
                  identifierOffsets: [59 ..< 62])
    expectMatches(.init(name: .qualified("receivers.(()->Unit).run")), in: result,
                  identifierOffsets: [86 ..< 89])
    expectMatches(.init(name: .qualified("receivers.suspend(()->Unit).ready")), in: result,
                  identifierOffsets: [232 ..< 237])
}

@Test(arguments: ["=", "by"])
func kotlinDetachedInitializerErrorsInvalidateOnlyTheirPropertyHeaders(introducer: String) throws {
    let fixture = try kotlinFixture("detached-initializers")
    let snapshot = SourceSnapshot(text: fixture.text.replacingOccurrences(of: "= ;", with: "\(introducer) ;"),
                                  language: .kotlin)
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.qualifiedName) == [
        "stored", "after",
    ])
    #expect(result.declarations.map { $0.headerRange.flatMap(snapshot.text(in:)) } == [
        nil, "fun after()",
    ])
    #expect(result.diagnostics.map { $0.range.flatMap(snapshot.text(in:)) } == [introducer])
}

@Test func kotlinRecoverySeparatorsAndBodiesPreserveSoundHeaders() throws {
    let cases: [(String, [String], [String?], String)] = [
        ("val separated: Int; =\n", ["separated"], ["val separated: Int"], "=\n"),
        ("fun body() {\n    val local: Int =\n}\n", ["body", "body.local"], ["fun body()", nil], "="),
        ("val computed: Int\n    get() {\n        val broken: Int =\n    }\n",
         ["computed", "computed.broken"], ["val computed: Int", nil], "="),
        ("fun functionBody(value: Int) =\n", ["functionBody"], ["fun functionBody(value: Int)"], "="),
        ("class Parameters(val broken: Int = , val healthy: Int = 1)\n",
         ["Parameters", "Parameters.broken", "Parameters.healthy"], [nil, nil, "val healthy: Int = 1"], "="),
    ]
    for (source, names, headers, diagnosticText) in cases {
        let snapshot = SourceSnapshot(text: source, language: .kotlin)
        let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
        try expectSnapshotContract(result, from: snapshot)
        #expect(result.declarations.map(\.qualifiedName) == names, "Source: \(source)")
        #expect(result.declarations.map { $0.headerRange.flatMap(snapshot.text(in:)) } == headers, "Source: \(source)")
        #expect(
            result.diagnostics.map { $0.range.flatMap(snapshot.text(in:)) } == [diagnosticText],
            "Source: \(source)"
        )
        if let function = kotlinCandidates("functionBody", in: result).first {
            #expect(function.signature?.parameters.map(\.typeSyntax) == ["Int"])
        }
        if let type = kotlinCandidates("Parameters", in: result).first {
            #expect(type.signature == nil)
        }
    }
}

@Test(arguments: ["val x =\n", "val x by\n", "class C(val x: Int = )\n"])
func kotlinDetachedInitializersAtEOFKeepDeclarationsAndDiagnostics(source: String) throws {
    let snapshot = SourceSnapshot(text: source, language: .kotlin)
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(!result.diagnostics.isEmpty)
    let property = try #require(kotlinCandidates("x", in: result).first)
    #expect(property.headerRange == nil)
    #expect(snapshot.text(in: property.identifierRange) == "x")
}

@Test(arguments: ["\n", "\r\n"])
func kotlinWhenSubjectsPreserveBindingsInitializerScopesAndSourceRanges(newline: String) throws {
    let fixture = try kotlinFixture("when-subjects")
    let snapshot = SourceSnapshot(text: fixture.text.replacingOccurrences(of: "\n", with: newline), language: .kotlin)
    let result = try TreeSitterKotlinExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.qualifiedName) == [
        "cases.outer", "cases.outer.café", "cases.outer.café.helper", "cases.outer.branch", "cases.outer.café",
        "cases.stored", "cases.stored.local", "cases.Container", "cases.Container.stored",
        "cases.Container.stored.memberSubject",
    ])
    #expect(result.declarations.map(\.kind) == [
        .function, .variable, .function, .variable, .variable, .property, .variable, .type, .property, .variable,
    ])
    #expect(kotlinCandidates("helper", in: result).first?.enclosingScopes == ["outer", "café"])
    #expect(kotlinCandidates("branch", in: result).first?.enclosingScopes == ["outer"])
    let subjects = kotlinCandidates("café", in: result)
    let expectedHeaders = [
        "val `café` = run {\n        fun helper() = input\n        helper()\n    }",
        "val `café` = 2",
    ].map { $0.replacingOccurrences(of: "\n", with: newline) }
    #expect(subjects.map { $0.headerRange.flatMap(snapshot.text(in:)) } == expectedHeaders)
    #expect(subjects.map { snapshot.text(in: $0.declarationRange) } == expectedHeaders)
    #expect(subjects.map { snapshot.text(in: $0.identifierRange) } == ["`café`", "`café`"])
    let identifiers = newline == "\n" ? [53 ..< 60, 205 ..< 212] : [56 ..< 63, 216 ..< 223]
    expectMatches(.init(name: .qualified("cases.outer.café")), in: result, identifierOffsets: identifiers)
    for subject in subjects {
        #expect(SourceSnapshot(text: snapshot.text, language: .kotlin).text(in: subject.declarationRange) == nil)
    }
}
