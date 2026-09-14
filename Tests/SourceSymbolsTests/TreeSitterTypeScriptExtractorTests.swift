import Foundation
import SourceSymbols
import Testing

private func typeScriptFixture(_ name: String, language: SourceLanguage = .typescript) throws -> SourceSnapshot {
    let ext = language == .tsx ? "tsx" : "ts"
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext,
                                             subdirectory: "Fixtures/TypeScript"))
    return try SourceSnapshot(text: String(contentsOf: url, encoding: .utf8), language: language)
}

private func typeScriptCandidates(_ name: String, in result: ExtractionResult) -> [Declaration] {
    result.declarations.filter { $0.name == name }
}

private struct TypeScriptFixtureExpectation: Decodable {
    let declarations: [ExpectedDeclaration]
    let diagnostics: [[Int]]
}

@Test(arguments: ["declarations", "unicode-lf", "unicode-crlf", "recovery", "incomplete", "component"])
func typeScriptPermanentCorpus(name: String) throws {
    let snapshot = try typeScriptFixture(name, language: name == "component" ? .tsx : .typescript)
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json",
                                             subdirectory: "Fixtures/TypeScript"))
    let expected = try JSONDecoder().decode(TypeScriptFixtureExpectation.self, from: Data(contentsOf: url))
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    try expectBackendContract(result, from: snapshot, declarations: expected.declarations,
                              diagnosticRanges: expected.diagnostics.map { $0[0] ..< $0[1] })
}

@Test func typeScriptOverloadsRemainAmbiguousWithPreciseHeaders() throws {
    let snapshot = try typeScriptFixture("declarations")
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    let choices = typeScriptCandidates("choose", in: result)
    #expect(choices.count == 3)
    #expect(choices.map(\.qualifiedName) == Array(repeating: "App.Tools.choose", count: 3))
    #expect(choices.map { $0.headerRange.flatMap(snapshot.text) } == [
        "export function choose(value: string): string",
        "export function choose(value: number): number",
        "export function choose(value: string | number): string | number",
    ])
    expectMatches(.init(name: .qualified("App.Tools.choose")), in: result,
                  identifierOffsets: choices.map(\.identifierRange.utf8Offsets))
    expectMatches(.init(name: .short("choose"), parameterTypes: ["number"]), in: result,
                  identifierOffsets: [choices[1].identifierRange.utf8Offsets])
    expectMatches(.init(name: .short("choose"), signature: choices[0].signature), in: result,
                  identifierOffsets: [choices[0].identifierRange.utf8Offsets])
    expectMatches(.init(name: .short("choose()")), in: result, identifierOffsets: [])
    expectMatches(.init(name: .qualified("App.Tools.absent")), in: result, identifierOffsets: [])
    #expect(result.declarations.allSatisfy { $0.callableName == nil && $0.qualifiedCallableName == nil })
    let client = try #require(typeScriptCandidates("Client", in: result).first)
    #expect(client.headerRange.flatMap(snapshot.text)
        == "@sealed\n  export abstract class Client<T extends Item> implements Store<T>")
    let namespace = try #require(result.declarations.first)
    #expect(namespace.name == "Tools" && namespace.qualifiedName == "App.Tools")
    #expect(namespace.headerRange.flatMap(snapshot.text) == "export namespace App.Tools")
    #expect(typeScriptCandidates("load", in: result).first?.qualifiedName == "\"remote\".load")
}

@Test func typeScriptSignaturesRetainAnnotationsOptionalityAndDefaults() throws {
    let snapshot = try typeScriptFixture("signatures")
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
    let collect = try #require(typeScriptCandidates("collect", in: result).first)
    #expect(collect.signature == CallableSignature(parameters: [
            .init(name: "value", typeSyntax: "T"),
            .init(name: "optional", typeSyntax: "number", isOptional: true),
            .init(name: "fallback", typeSyntax: "string", hasDefaultValue: true),
            .init(name: "rest", typeSyntax: "readonly T[]", passing: .variadicPositional),
        ], genericParameters: "<T extends { id: string } = { id: string }>", effects: ["async"],
        returnType: "Promise<T[]>"))
    #expect(typeScriptCandidates("destructured", in: result).first?.signature?.parameters == [
        .init(typeSyntax: "{ id: string }"), .init(typeSyntax: "string[]", hasDefaultValue: true),
    ])
    let receiver = try #require(typeScriptCandidates("receiver", in: result).first)
    #expect(receiver.signature == nil && receiver.headerRange != nil)
    expectMatches(.init(name: .short("receiver"), parameterTypes: ["string"]), in: result, identifierOffsets: [])
    #expect(typeScriptCandidates("untyped", in: result).first?.signature?.parameters == [
        .init(name: "value"), .init(name: "fallback", hasDefaultValue: true),
    ])
    #expect(typeScriptCandidates("predicate", in: result).first?.signature?.returnType == "value is string")
    #expect(typeScriptCandidates("assertion", in: result).first?.signature?.returnType == "asserts value is string")
    #expect(typeScriptCandidates("sequence", in: result).first?.signature?.effects == ["*"])
    #expect(typeScriptCandidates("arrow", in: result).first?.signature == .init(parameters: [
        .init(name: "value", typeSyntax: "T"), .init(name: "optional", typeSyntax: "T", isOptional: true),
    ], genericParameters: "<T,>", returnType: "T"))
    #expect(typeScriptCandidates("simple", in: result).first?.signature?.parameters == [.init(name: "value")])
    #expect(typeScriptCandidates("wrapped", in: result).first?.signature?.parameters == [
        .init(name: "value", typeSyntax: "number"),
    ])
    #expect(typeScriptCandidates("inner", in: result).first?.qualifiedName == "named.inner")
    #expect(typeScriptCandidates("local", in: result).first?.qualifiedName == "named.inner.local")
    #expect(typeScriptCandidates("generator", in: result).first?.signature?.effects == ["*"])
}

@Test func typeScriptBindingsAndAnonymousScopesExcludeReferencesAndParameters() throws {
    let snapshot = try typeScriptFixture("scopes")
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.declarations.map(\.qualifiedName) == [
        "renamed", "shorthand", "head", "tail", "missing", "rest", "first", "second", "object",
        "object.value", "object.shorthand", "object.run", "object.run.local", "object.run.inner",
        "object.constructor", "object.current", "object.callback", "object.callback.result", "object.\"quoted-name\"",
        "Factory", "Factory.Named", "Factory.Named.field", "Factory.Named.field.seed", "Factory.Named.method",
        "Factory.Named.method.nested", "Anonymous", "Anonymous.method", "Anonymous.method.local",
        "outer", "outer.inDefault", "outer.callback", "outer.callback.local", "outer.duplicate", "outer.duplicate",
        "entry", "loopLocal", "Shape", "Shape.child", "Shape.method",
    ])
    #expect(typeScriptCandidates("constructor", in: result).first?.kind == .method)
    let duplicates = typeScriptCandidates("duplicate", in: result)
    expectMatches(.init(name: .qualified("outer.duplicate")), in: result,
                  identifierOffsets: duplicates.map(\.identifierRange.utf8Offsets))
    let grouped = Array(result.declarations.prefix(6))
    #expect(grouped.allSatisfy { snapshot.text(in: $0.declarationRange)
            == "const { key: renamed, shorthand, nested: [head, ...tail], missing = 1, ...rest } = source;"
    })
}

@Test func tsxUsesJSXGrammarWithoutExtractingTextOrAttributes() throws {
    let snapshot = try typeScriptFixture("component", language: .tsx)
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.qualifiedName) == [
        "Props", "Props.title", "View", "View.render", "View.nested", "App", "fragment",
    ])
    #expect(typeScriptCandidates("View", in: result).first?.signature?.parameters == [.init(typeSyntax: "Props")])
    #expect(typeScriptCandidates("render", in: result).first?.signature?.genericParameters == "<T,>")
    #expect(typeScriptCandidates("App", in: result).first?.signature?.parameters == [.init(typeSyntax: "Props")])
    try expectSnapshotContract(result, from: snapshot)
}

@Test func typeScriptRecoveredBodiesPreserveHeadersButDamagedHeadersDoNot() throws {
    let snapshot = try typeScriptFixture("recovery")
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    for name in ["bodyError", "method", "later"] {
        let declaration = try #require(typeScriptCandidates(name, in: result).first)
        #expect(declaration.signature != nil && declaration.headerRange != nil)
    }
    for name in ["headerError", "missing"] {
        let declaration = try #require(typeScriptCandidates(name, in: result).first)
        #expect(declaration.signature == nil && declaration.headerRange == nil)
        expectMatches(.init(name: .short(name), parameterTypes: [nil]), in: result, identifierOffsets: [])
    }
    #expect(result.diagnostics.map(\.message) == [
        "Tree-sitter: unrecognized syntax", "Tree-sitter: unrecognized syntax", "Tree-sitter: missing )",
        "Tree-sitter: unrecognized syntax",
    ])
}

@Test(arguments: ["unicode-lf", "unicode-crlf"])
func typeScriptUnicodeAndPositionsPreserveOriginalBytes(name: String) throws {
    let snapshot = try typeScriptFixture(name)
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    #expect(snapshot.text.utf8.contains(13) == (name == "unicode-crlf"))
    let function = try #require(typeScriptCandidates("café", in: result).first)
    #expect(snapshot.text(in: function.identifierRange)?.utf8.elementsEqual("café".utf8) == true)
    let positions = SourcePositionIndex(snapshot: snapshot)
    #expect(positions.position(in: function.identifierRange, columnEncoding: .utf16)?.line == 3)
    #expect(positions.position(in: function.identifierRange, columnEncoding: .utf16)?.column == 19)
    #expect(SourceSnapshot(text: snapshot.text, language: .typescript).text(in: function.identifierRange) == nil)
}

@Test func typeScriptLanguagesAreExplicitAndEmbeddedNULDoesNotTruncate() throws {
    for language in [SourceLanguage.swift, .ruby] {
        #expect(throws: ExtractionError.self) {
            try TreeSitterTypeScriptExtractor().extract(from: SourceSnapshot(text: "", language: language))
        }
    }
    for language in [SourceLanguage.typescript, .tsx] {
        #expect(throws: ExtractionError.self) {
            try TreeSitterSwiftExtractor().extract(from: SourceSnapshot(text: "", language: language))
        }
        #expect(throws: ExtractionError.self) {
            try TreeSitterRubyExtractor().extract(from: SourceSnapshot(text: "", language: language))
        }
        let empty = try TreeSitterTypeScriptExtractor().extract(from: SourceSnapshot(text: "", language: language))
        #expect(empty.declarations.isEmpty && empty.diagnostics.isEmpty)
        let snapshot = SourceSnapshot(text: "function before() {}\n\0\nfunction after() {}", language: language)
        let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
        #expect(result.declarations.map(\.name) == ["before", "after"])
        #expect(!result.diagnostics.isEmpty)
        try expectSnapshotContract(result, from: snapshot)
    }
}

@Test func typeScriptExtractorSupportsConcurrentDialects() async throws {
    let extractor = TreeSitterTypeScriptExtractor()
    let typescript = try typeScriptFixture("declarations")
    let tsx = try typeScriptFixture("component", language: .tsx)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0 ..< 16 {
            group.addTask {
                let snapshot = index.isMultiple(of: 2) ? typescript : tsx
                let result = try extractor.extract(from: snapshot)
                #expect(result.diagnostics.isEmpty)
                #expect(result.declarations.count == (index.isMultiple(of: 2) ? 30 : 7))
                try expectSnapshotContract(result, from: snapshot)
            }
        }
        try await group.waitForAll()
    }
}

@Test func typeScriptHeadersRetainTriviaAndStopAtSyntaxBodies() throws {
    let snapshot = try typeScriptFixture("headers")
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
    let fetch = try #require(typeScriptCandidates("fetchValue", in: result).first)
    #expect(fetch.headerRange.flatMap(snapshot.text) == """
    export default async function fetchValue<T /* generic */ extends { id: string }>(
      value: T = (() => { const fallback = { id: "x" }; return fallback; })() as T
    ): Promise<T>
    """)
    #expect(fetch.signature?.genericParameters == "<T /* generic */ extends { id: string }>")
    #expect(fetch.signature?.parameters == [.init(name: "value", typeSyntax: "T", hasDefaultValue: true)])
    #expect(typeScriptCandidates("ambient", in: result).first?.headerRange.flatMap(snapshot.text)
        == "export declare function ambient(value?: { text: string }): void")
    #expect(typeScriptCandidates("Ambient", in: result).first?.headerRange.flatMap(snapshot.text)
        == "declare namespace Ambient")
    #expect(typeScriptCandidates("nested", in: result).map(\.qualifiedName) == ["Ambient.nested", "Symbols.nested"])
    #expect(typeScriptCandidates("MapValue", in: result).first?.headerRange.flatMap(snapshot.text)
        == "export type MapValue = { readonly key: string; }")
    let grouped = typeScriptCandidates("grouped", in: result) + typeScriptCandidates("callback", in: result)
    #expect(grouped.count == 2)
    #expect(grouped.allSatisfy { $0.headerRange.flatMap(snapshot.text)
            == "const grouped = 1, callback = (value: string): string => { return value; }"
    })
    #expect(typeScriptCandidates("\"quoted\"", in: result).first?.qualifiedName == "Symbols.\"quoted\"")
    #expect(typeScriptCandidates("42", in: result).first?.kind == .method)
    #expect(typeScriptCandidates("#private", in: result).first?.signature?.parameters == [
        .init(name: "value", typeSyntax: "number"),
    ])
    #expect(typeScriptCandidates("block", in: result).first?.qualifiedName == "Symbols.block")
    #expect(typeScriptCandidates("method", in: result).first?.qualifiedName == "method")
    let loop = try TreeSitterTypeScriptExtractor().extract(from: typeScriptFixture("scopes"))
    let entry = try #require(typeScriptCandidates("entry", in: loop).first)
    #expect(loop.snapshot.text(in: entry.declarationRange) == "const entry")
    #expect(entry.headerRange.flatMap(loop.snapshot.text) == "const entry")
}

@Test func typeScriptWrapperErrorsInvalidateSignaturesAndMissingBodyClosersPreserveThem() throws {
    let snapshot = try typeScriptFixture("wrapper-recovery")
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    let wrapped = try #require(typeScriptCandidates("wrapped", in: result).first)
    #expect(wrapped.headerRange == nil && wrapped.signature == nil)
    expectMatches(.init(name: .short("wrapped"), parameterTypes: ["string"]), in: result, identifierOffsets: [])
    let recovered = try #require(typeScriptCandidates("recovered", in: result).first)
    #expect(recovered.headerRange.flatMap(snapshot.text) == "export function recovered(value: string): void")
    #expect(recovered.signature == .init(parameters: [.init(name: "value", typeSyntax: "string")], returnType: "void"))
    #expect(snapshot.text(in: recovered.declarationRange)
        == "export function recovered(value: string): void { const local = 1;")
    #expect(typeScriptCandidates("local", in: result).first?.qualifiedName == "recovered.local")
    #expect(result.diagnostics.map { $0.range?.utf8Offsets } == [7 ..< 11, 118 ..< 118])
    try expectSnapshotContract(result, from: snapshot)
}

@Test func typeScriptDialectAndStaticConstructorsAreNotInferredFromNames() throws {
    let snapshot = try typeScriptFixture("dialect")
    let extractor = TreeSitterTypeScriptExtractor()
    let plain = try extractor.extract(from: snapshot)
    #expect(plain.diagnostics.isEmpty)
    #expect(plain.declarations.map(\.name) == ["value"])
    let tsx = try extractor.extract(from: SourceSnapshot(text: snapshot.text, language: .tsx))
    #expect(!tsx.diagnostics.isEmpty)
    try expectSnapshotContract(plain, from: snapshot)
    try expectSnapshotContract(tsx, from: tsx.snapshot)
    let headers = try extractor.extract(from: typeScriptFixture("headers"))
    let constructor = try #require(typeScriptCandidates("constructor", in: headers).first)
    #expect(constructor.kind == .method && constructor.qualifiedName == "Symbols.constructor")
    #expect(constructor.signature == .init(parameters: []))
}
