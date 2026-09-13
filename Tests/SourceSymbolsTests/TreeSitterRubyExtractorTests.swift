import Foundation
import SourceSymbols
import Testing

private func rubyFixture(_ name: String) throws -> SourceSnapshot {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "rb", subdirectory: "Fixtures/Ruby"))
    return try SourceSnapshot(text: String(contentsOf: url, encoding: .utf8), language: .ruby)
}

private struct RubyExpectedFixture: Decodable {
    let declarations: [ExpectedDeclaration]
    let diagnosticRanges: [[Int]]
    let qualifiedNames: [String]
}

private func rubyCandidates(_ name: String, in result: ExtractionResult) -> [Declaration] {
    result.declarations.filter { $0.name == name }
}

@Test(arguments: ["declarations", "unicode-lf", "unicode-crlf", "recovery", "incomplete"])
func rubyDeclarationCorpus(name: String) throws {
    let snapshot = try rubyFixture(name)
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Ruby"))
    let expected = try JSONDecoder().decode(RubyExpectedFixture.self, from: Data(contentsOf: url))
    let result = try TreeSitterRubyExtractor().extract(from: snapshot)
    try expectBackendContract(result, from: snapshot, declarations: expected.declarations,
                              diagnosticRanges: expected.diagnosticRanges.map { $0[0] ..< $0[1] })
    #expect(result.declarations.map(\.qualifiedName) == expected.qualifiedNames)
}

@Test func rubyRedefinitionsAndReopeningsRemainAmbiguous() throws {
    let result = try TreeSitterRubyExtractor().extract(from: rubyFixture("declarations"))
    let carts = rubyCandidates("Cart", in: result)
    #expect(carts.count == 3)
    expectMatches(.init(name: .qualified("Shop::Cart")), in: result,
                  identifierOffsets: carts.map(\.identifierRange.utf8Offsets))
    let methods = rubyCandidates("add", in: result)
    #expect(methods.count == 2)
    expectMatches(.init(name: .qualified("Shop::Cart#add")), in: result,
                  identifierOffsets: methods.map(\.identifierRange.utf8Offsets))
    try expectMatches(.init(name: .qualified("Shop::Cart#add"), parameterTypes: [nil]), in: result,
                      identifierOffsets: [#require(methods.last).identifierRange.utf8Offsets])
    let signature = try #require(methods.first?.signature)
    try expectMatches(.init(name: .short("add"), signature: signature), in: result,
                      identifierOffsets: [#require(methods.first).identifierRange.utf8Offsets])
    expectMatches(.init(name: .short("Add")), in: result, identifierOffsets: [])
    expectMatches(.init(name: .short("add"), parameterTypes: ["Object"]), in: result, identifierOffsets: [])
    expectMatches(.init(name: .short("add(_:)")), in: result, identifierOffsets: [])
    #expect(result.declarations.allSatisfy { $0.callableName == nil && $0.qualifiedCallableName == nil })
}

@Test func rubyParametersPreservePassingNamesDefaultsAndAbsentAnnotations() throws {
    let result = try TreeSitterRubyExtractor().extract(from: rubyFixture("parameters"))
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.count == 10)
    let deliver = try #require(rubyCandidates("deliver", in: result).first)
    #expect(deliver.signature == CallableSignature(parameters: [
        .init(name: "payload"),
        .init(name: "count", hasDefaultValue: true),
        .init(name: "rest", passing: .variadicPositional),
        .init(name: "required", argumentLabel: "required", passing: .keyword),
        .init(name: "timeout", argumentLabel: "timeout", passing: .keyword, hasDefaultValue: true),
        .init(name: "options", passing: .variadicKeyword),
        .init(name: "block", passing: .block),
    ]))
    #expect(rubyCandidates("bare", in: result).first?.signature?.parameters == [
        .init(name: "value"), .init(name: "optional", hasDefaultValue: true),
        .init(name: "key", argumentLabel: "key", passing: .keyword),
        .init(name: "flag", argumentLabel: "flag", passing: .keyword, hasDefaultValue: true),
    ])
    #expect(rubyCandidates("anonymous", in: result).first?.signature?.parameters == [
        .init(passing: .variadicPositional), .init(passing: .variadicKeyword), .init(passing: .block),
    ])
    for name in ["empty", "parenthesized"] {
        let method = try #require(rubyCandidates(name, in: result).first)
        #expect(method.signature == .init(parameters: []))
        expectMatches(.init(name: .short(name), parameterTypes: []), in: result,
                      identifierOffsets: [method.identifierRange.utf8Offsets])
    }
    for name in ["forwarded", "reject_keywords", "destructured"] {
        #expect(rubyCandidates(name, in: result).count == 1)
        #expect(rubyCandidates(name, in: result).first?.signature == nil)
        expectMatches(.init(name: .short(name), parameterTypes: []), in: result, identifierOffsets: [])
    }
    #expect(rubyCandidates("defaults", in: result).first?.signature?.parameters == [
        .init(name: "callback", hasDefaultValue: true), .init(name: "text", hasDefaultValue: true),
        .init(name: "pattern", hasDefaultValue: true),
    ])
}

@Test func rubySyntaxScopesDoNotInferRuntimeLookup() throws {
    let snapshot = try rubyFixture("syntax")
    let result = try TreeSitterRubyExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.qualifiedName) == [
        "Outer", "Outer::Inner::Nested", "Outer::Inner::Nested.run", "Outer::Inner::Nested#value=",
        "::Root", "::Root#run", "Outer::Outer.helper", "Choice", "Choice#run", "Choice", "Choice#run",
        "<< client", "client.refresh!", "<< client::<< self", "client.singleton_class.deep",
        "(factory.call).build", "hidden",
    ])
    #expect(rubyCandidates("Nested", in: result).first?.enclosingScopes == ["Outer"])
    #expect(rubyCandidates("value=", in: result).first?.enclosingScopes == ["Outer", "Inner::Nested"])
    #expect(rubyCandidates("Root", in: result).first?.enclosingScopes == ["Outer"])
    #expect(rubyCandidates("deep", in: result).first?.enclosingScopes == ["<< client", "<< self"])
    let hidden = try #require(rubyCandidates("hidden", in: result).first)
    #expect(snapshot.text(in: hidden.declarationRange) == "def hidden; end")
}

@Test func rubyConstantAssignmentsAndStaticAliasesExcludeReferencesAndDynamicCalls() throws {
    let snapshot = try rubyFixture("bindings")
    let result = try TreeSitterRubyExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.qualifiedName) == [
        "Config", "Config::VERSION", "Config::A", "Config::B", "Config::Namespace::C", "::ROOT",
        "Config#fresh", "Config#ready?",
    ])
    #expect(result.declarations.map(\.kind) == [
        .type, .variable, .variable, .variable, .variable, .variable, .method, .method,
    ])
    let grouped = result.declarations.filter { ["A", "B", "C"].contains($0.name) }
    #expect(grouped.count == 3)
    #expect(grouped.allSatisfy { snapshot.text(in: $0.declarationRange) == "A, (B, Namespace::C) = 1, [2, 3]" })
    let alias = try #require(rubyCandidates("ready?", in: result).first)
    #expect(alias.signature == nil)
    #expect(snapshot.text(in: alias.identifierRange) == ":ready?")
}

@Test func rubyDamagedHeadersDifferFromRecoveredBodies() throws {
    let result = try TreeSitterRubyExtractor().extract(from: rubyFixture("recovery"))
    #expect(!result.diagnostics.isEmpty)
    #expect(rubyCandidates("body_error", in: result).first?.signature == .init(parameters: [.init(name: "value")]))
    #expect(rubyCandidates("header_error", in: result).first?.signature == nil)
    expectMatches(.init(name: .short("header_error"), parameterTypes: []), in: result, identifierOffsets: [])
    #expect(result.diagnostics.allSatisfy { $0.severity == .error })
}

@Test(arguments: ["unicode-lf", "unicode-crlf"])
func rubyUnicodeBytesRemainSnapshotBound(name: String) throws {
    let snapshot = try rubyFixture(name)
    #expect(snapshot.text.utf8.contains(13) == (name == "unicode-crlf"))
    let result = try TreeSitterRubyExtractor().extract(from: snapshot)
    let method = try #require(rubyCandidates("café", in: result).first)
    #expect(snapshot.text(in: method.identifierRange)?.utf8.elementsEqual("café".utf8) == true)
    #expect(method.signature?.parameters == [
        .init(name: "value"), .init(name: "clé", argumentLabel: "clé", passing: .keyword, hasDefaultValue: true),
    ])
    let other = SourceSnapshot(text: snapshot.text, language: .ruby)
    #expect(other.text(in: method.identifierRange) == nil)
}

@Test func rubyAndSwiftRejectEachOthersLanguage() throws {
    #expect(throws: ExtractionError.self) {
        try TreeSitterRubyExtractor().extract(from: SourceSnapshot(text: "", language: .swift))
    }
    #expect(throws: ExtractionError.self) {
        try TreeSitterSwiftExtractor().extract(from: SourceSnapshot(text: "", language: .ruby))
    }
}

@Test func rubyEmptyInputAndEmbeddedNULDoNotTruncate() throws {
    let empty = try TreeSitterRubyExtractor().extract(from: SourceSnapshot(text: "", language: .ruby))
    #expect(empty.declarations.isEmpty && empty.diagnostics.isEmpty)
    let snapshot = SourceSnapshot(text: "def before; end\n\0\ndef after; end\n", language: .ruby)
    let result = try TreeSitterRubyExtractor().extract(from: snapshot)
    #expect(result.declarations.map(\.name) == ["before", "after"])
    #expect(!result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
}

@Test func rubyExtractorCanBeReusedConcurrently() async throws {
    let extractor = TreeSitterRubyExtractor()
    let snapshot = try rubyFixture("declarations")
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0 ..< 16 {
            group.addTask {
                let result = try extractor.extract(from: snapshot)
                #expect(result.diagnostics.isEmpty)
                #expect(result.declarations.count == 19)
                try expectSnapshotContract(result, from: snapshot)
            }
        }
        try await group.waitForAll()
    }
}

@Test func rubyDelayedHeredocBodiesBelongToTheirDeclarationAndScope() throws {
    let snapshot = try rubyFixture("heredocs")
    let result = try TreeSitterRubyExtractor().extract(from: snapshot)
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.qualifiedName) == [
        "DOC",
        "message",
        "message::inside",
        "PAIR",
        "Host",
        "Host#body",
        "OTHER",
        "owned_by_constant",
        "later",
        "default_doc",
    ])
    let expected = [
        "DOC = <<~TEXT\n  class Fake; end\nTEXT",
        "def message = <<~TEXT\n  #{def inside; end}\nTEXT",
        "def inside; end",
        "PAIR = [<<~FIRST, <<~SECOND]\n  one\nFIRST\n  two\nSECOND",
        "class Host\n  def body\n    <<~TEXT\n      def fake; end\n    TEXT\n  end\nend",
        "def body\n    <<~TEXT\n      def fake; end\n    TEXT\n  end",
        "OTHER = <<~TEXT; def later; end\n  #{def owned_by_constant; end}\nTEXT",
        "def owned_by_constant; end",
        "def later; end",
        "def default_doc(value = <<~TEXT)\n  content\nTEXT\nend",
    ]
    #expect(result.declarations.map { snapshot.text(in: $0.declarationRange) } == expected)
    #expect(rubyCandidates("default_doc", in: result).first?.signature?.parameters == [
        .init(name: "value", hasDefaultValue: true),
    ])
    try expectSnapshotContract(result, from: snapshot)
}

@Test func rubyMissingTokensHaveZeroWidthSnapshotRanges() throws {
    let snapshot = try rubyFixture("missing")
    let result = try TreeSitterRubyExtractor().extract(from: snapshot)
    #expect(result.declarations.map(\.name) == ["f"])
    #expect(result.declarations.first?.signature == nil)
    #expect(result.diagnostics.map(\.message) == ["Tree-sitter: missing )"])
    #expect(result.diagnostics.map { $0.range?.utf8Offsets } == [7 ..< 7])
    try expectSnapshotContract(result, from: snapshot)
}
