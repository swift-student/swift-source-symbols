import Foundation
import SourceSymbols
import Testing

private func expectHeader(_ declaration: Declaration, _ expected: String, in snapshot: SourceSnapshot) throws {
    let header = try #require(declaration.headerRange)
    let occurrence = try #require(snapshot.text.range(of: expected, options: .literal))
    let start = snapshot.text.utf8.distance(from: snapshot.text.utf8.startIndex, to: occurrence.lowerBound)
    #expect(header.utf8Offsets == start ..< start + expected.utf8.count)
    #expect(try #require(snapshot.text(in: header)).utf8.elementsEqual(expected.utf8))
    let foreign = SourceSnapshot(text: snapshot.text, language: snapshot.language)
    #expect(foreign.text(in: header) == nil)
    #expect(foreign.utf16Offsets(for: header) == nil)
}

@Test(arguments: ["\n", "\r\n"])
func swiftHeadersPreserveSourceSyntaxAndExcludeOnlyDirectBodies(newline: String) throws {
    let source = try fixture("headers").text.replacingOccurrences(of: "\n", with: newline)
    let snapshot = SourceSnapshot(text: source, language: .swift)
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.diagnostics.isEmpty)
    let expected: [(String, String)] = [
        ("Store", """
        @available(*, deprecated, message: "use { replacement }")
        public struct Store<T>: Sendable where T: Sendable
        """),
        ("Store.refresh", "func refresh(force: Bool)"),
        ("Store.refresh", "func refresh(force: Int)"),
        ("Store.transform", """
        @Header({ ["{": "}"] })
            public func transform<U>(
                _ value: U,
                using callback: @Sendable (U) -> String = { _ in "{}" }
            ) async throws(Failure) -> String
            where U: Equatable
        """),
        ("Store.computed", "var computed: Int"),
        ("Store.observed", "var observed = 0"),
        ("Store.closure", "let closure: () -> Int = { { 1 }() }"),
        ("Store.first", "let first = 1, second: String = \"two\""),
        ("Store.second", "let first = 1, second: String = \"two\""),
        ("Store.left", "let (left, right) = (1, 2)"),
        ("Store.right", "let (left, right) = (1, 2)"),
        ("Store.init", "init?(value: T)"),
        ("Store.init", "init!(other value: T)"),
        ("Store.subscript", "subscript(key index: Int) -> T"),
        ("Store.Pair", "typealias Pair = (T, T)"),
        ("Store", "extension Store where T: Equatable"),
        ("Headers", "protocol Headers"),
        ("Headers.Item", "associatedtype Item: Equatable"),
        ("Headers.required", "var required: Item"),
        ("Headers.bodyless", "func bodyless(value local: Item) async throws -> Item"),
        ("Headers.init", "init(value: Item)"),
        ("Headers.subscript", "subscript(index: Int) -> Item"),
        ("Event", "enum Event"),
        ("Event.payload", "indirect case payload(value: Int, callback: (Int) -> String), ready"),
        ("Event.ready", "indirect case payload(value: Int, callback: (Int) -> String), ready"),
        ("Raw", "enum Raw: Int"),
        ("Raw.one", "case one = 1, two = 2"),
        ("Raw.two", "case one = 1, two = 2"),
        ("Lifetime", "class Lifetime"),
        ("Lifetime.deinit", "deinit"),
        ("café", "func café(\n    😀 é: String = \"😀\"\n) -> String"),
    ]
    #expect(result.declarations.map(\.qualifiedName) == expected.map(\.0))
    for (declaration, (_, header)) in zip(result.declarations, expected) {
        try expectHeader(declaration, header.replacingOccurrences(of: "\n", with: newline), in: snapshot)
    }
    let overloads = candidates(.init(name: .qualified("Store.refresh(force:)")), in: result)
    #expect(overloads.count == 2)
    #expect(overloads.map { $0.signature?.parameters.map(\.typeSyntax) } == [["Bool"], ["Int"]])
    #expect(overloads.first?.headerRange != overloads.last?.headerRange)
}

@Test(arguments: ["\n", "\r\n"])
func rubyHeadersRemainIndependentOfRepresentableSignatures(newline: String) throws {
    let url = try #require(Bundle.module.url(forResource: "headers", withExtension: "rb",
                                             subdirectory: "Fixtures/Ruby"))
    let source = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\n", with: newline)
    let snapshot = SourceSnapshot(text: source, language: .ruby)
    let result = try TreeSitterRubyExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.diagnostics.isEmpty)
    let expected: [(String, String?)] = [
        ("Shop", "module Shop"),
        ("Shop::Cart", "class Cart < Factory.build({key: -> { 1 }})"),
        ("Shop::Cart#refresh", "def refresh(force = true)"),
        ("Shop::Cart#refresh", "def refresh(force = 1)"),
        ("Shop::Cart.build", """
        def self.build(
              value = {key: -> { "{}" }},
              label: "😀",
              **options, &block
            )
        """),
        ("Shop::Cart#bare", "def bare value, label: \"ok\""),
        ("Shop::Cart#empty", "def empty"),
        ("Shop::Cart#forwarded", "def forwarded(...)"),
        ("Shop::Cart#destructured", "def destructured((left, right))"),
        ("Shop::Cart#reject", "def reject(**nil)"),
        ("Shop::Cart#again", "alias :again :refresh"),
        ("Shop::Cart::<< self", "class << self"),
        ("Shop::Cart.singleton", "def singleton"),
        ("Shop::Cart::FIRST", nil),
        ("Shop::Cart::SECOND", nil),
        ("default_doc", nil),
        ("body_doc", "def body_doc"),
        ("café", "def café(\n  value = \"😀\"\n)"),
    ]
    #expect(result.declarations.map(\.qualifiedName) == expected.map(\.0))
    for (declaration, (_, header)) in zip(result.declarations, expected) {
        if let header {
            try expectHeader(declaration, header.replacingOccurrences(of: "\n", with: newline), in: snapshot)
        } else {
            #expect(declaration.headerRange == nil)
        }
    }
    for name in ["forwarded", "destructured", "reject", "again"] {
        let declaration = try #require(result.declarations.first { $0.name == name })
        #expect(declaration.signature == nil)
        #expect(declaration.headerRange != nil)
    }
    let heredoc = try #require(result.declarations.first { $0.name == "default_doc" })
    #expect(heredoc.signature?.parameters.first?.hasDefaultValue == true)
}

@Test func recoveredSwiftHeadersRetainDiagnosticsAndAvailableDeclarations() throws {
    let snapshot = try fixture("incomplete")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(!result.diagnostics.isEmpty)
    let broken = try #require(result.declarations.first { $0.name == "broken" })
    #expect(broken.headerRange == nil)
    let recovered = try #require(result.declarations.first { $0.name == "recovered" })
    try expectHeader(recovered, "func recovered(value: Int)", in: snapshot)
    let openSnapshot = try fixture("incomplete-trivia")
    let openResult = try TreeSitterSwiftExtractor().extract(from: openSnapshot)
    #expect(!openResult.diagnostics.isEmpty)
    try expectHeader(#require(openResult.declarations.first), "struct Open", in: openSnapshot)
    let commentSnapshot = try fixture("header-comment-recovery")
    let commentResult = try TreeSitterSwiftExtractor().extract(from: commentSnapshot)
    #expect(!commentResult.diagnostics.isEmpty)
    try expectSnapshotContract(commentResult, from: commentSnapshot)
    let property = try #require(commentResult.declarations.first { $0.name == "computed" })
    try expectHeader(property, "var computed: Int", in: commentSnapshot)
}

@Test func rubyRecoveredHeadersDistinguishHeaderDamageFromBodyDamage() throws {
    let sources = [
        ("def broken(value = ); end", "broken", nil),
        ("def sound(value) @; end", "sound", "def sound(value)"),
        ("def bare value\n @\nend", "bare", "def bare value"),
        ("class Host\n @\nend", "Host", "class Host"),
    ]
    for (source, name, expected) in sources {
        let snapshot = SourceSnapshot(text: source, language: .ruby)
        let result = try TreeSitterRubyExtractor().extract(from: snapshot)
        try expectSnapshotContract(result, from: snapshot)
        #expect(!result.diagnostics.isEmpty)
        let declaration = try #require(result.declarations.first { $0.name == name })
        if let expected {
            try expectHeader(declaration, expected, in: snapshot)
        } else {
            #expect(declaration.headerRange == nil)
        }
    }
}

@Test func swiftHeadersPreserveInteriorCommentsAndExposeNoncontiguousGroups() throws {
    let snapshot = try fixture("header-groups")
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.name) == ["Groups", "first", "second", "comments"])
    for declaration in result.declarations where ["first", "second"].contains(declaration.name) {
        #expect(declaration.headerRange == nil)
        #expect(snapshot.text(in: declaration.declarationRange) == "var first = 0 { didSet {} }, second = 1")
    }
    let comments = try #require(result.declarations.last)
    try expectHeader(comments, """
    @Attr({ 1 })
        func comments(value /* label */ local: Int = /* default */ 1) -> /* return */ Int
    """, in: snapshot)
}

@Test func rubyNamespaceHeaderErrorsAreNotConfusedWithBodyErrors() throws {
    let url = try #require(Bundle.module.url(forResource: "header-recovery", withExtension: "rb",
                                             subdirectory: "Fixtures/Ruby"))
    let snapshot = try SourceSnapshot(text: String(contentsOf: url, encoding: .utf8), language: .ruby)
    let result = try TreeSitterRubyExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(!result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.name) == ["Broken", "Damaged", "Sound", "Host"])
    for declaration in result.declarations where ["Broken", "Damaged"].contains(declaration.name) {
        #expect(declaration.headerRange == nil)
    }
    for declaration in result.declarations where ["Sound", "Host"].contains(declaration.name) {
        try expectHeader(declaration, "class " + declaration.name, in: snapshot)
    }
}
