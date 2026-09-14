import SourceSymbolsCore
import Testing

@Test func declarationHeadersValidateSnapshotContainmentAndIdentifier() throws {
    let snapshot = SourceSnapshot(text: "// 😀\r\nfunc café() {} trailing", language: .swift)
    let foreign = SourceSnapshot(text: snapshot.text, language: .swift)
    let full = try #require(snapshot.range(9 ..< 24))
    let identifier = try #require(snapshot.range(14 ..< 19))
    let header = try #require(snapshot.range(9 ..< 21))
    let declaration = try Declaration(name: "café", qualifiedName: "café", kind: .function,
                                      identifierRange: identifier, declarationRange: full, headerRange: header)
    #expect(snapshot.text(in: declaration.identifierRange) == "café")
    #expect(snapshot.text(in: header) == "func café()")
    #expect(snapshot.text(in: declaration.declarationRange) == "func café() {}")
    #expect(declaration.signature == nil)
    #expect(throws: ExtractionError.self) {
        try ExtractionResult(snapshot: foreign, declarations: [declaration])
    }
    let invalidHeaders = try [
        #require(foreign.range(header.utf8Offsets)),
        #require(snapshot.range(0 ..< 21)),
        #require(snapshot.range(9 ..< 25)),
        #require(snapshot.range(9 ..< 14)),
        #require(snapshot.range(19 ..< 21)),
        #require(snapshot.range(14 ..< 14)),
    ]
    for invalidHeader in invalidHeaders {
        #expect(throws: ExtractionError.self) {
            try Declaration(name: "café", qualifiedName: "café", kind: .function,
                            identifierRange: identifier, declarationRange: full, headerRange: invalidHeader)
        }
    }
    // Invalid byte offsets never become SourceRange values, including inside an identifier's scalar.
    #expect(snapshot.range(9 ..< 18) == nil)
    #expect(snapshot.range(-1 ..< 21) == nil)
    #expect(snapshot.range(9 ..< 100) == nil)
    let unavailable = try Declaration(name: "café", qualifiedName: "café", kind: .function,
                                      identifierRange: identifier, declarationRange: full)
    #expect(unavailable.headerRange == nil)
}
