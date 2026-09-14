import SourceSymbolsCore
import Testing

@Test func sourcePositionsPreserveUnicodeScalarBoundaries() throws {
    let snapshot = SourceSnapshot(text: "a😀e\u{301}\r\né\r中\n", language: .swift)
    let index = SourcePositionIndex(snapshot: snapshot)
    // Offset, one-based line, UTF-8 column, UTF-16 column, specified from source bytes.
    let expected = [
        (0, 1, 1, 1), (1, 1, 2, 2), (5, 1, 6, 4), (6, 1, 7, 5),
        (8, 1, 9, 6), (9, 1, 10, 7), (10, 2, 1, 1), (12, 2, 3, 2),
        (13, 3, 1, 1), (16, 3, 4, 2), (17, 4, 1, 1),
    ]
    for (offset, line, utf8Column, utf16Column) in expected {
        let utf8 = try #require(index.position(atUTF8Offset: offset, columnEncoding: .utf8))
        let utf16 = try #require(index.position(atUTF8Offset: offset, columnEncoding: .utf16))
        #expect(utf8.snapshotID == snapshot.id)
        #expect(utf16.snapshotID == snapshot.id)
        #expect(utf8.utf8Offset == offset)
        #expect(utf16.utf8Offset == offset)
        #expect(utf8.line == line)
        #expect(utf16.line == line)
        #expect(utf8.column == utf8Column)
        #expect(utf16.column == utf16Column)
        #expect(utf8.columnEncoding == .utf8)
        #expect(utf16.columnEncoding == .utf16)
    }
    for offset in [Int.min, -1, 2, 3, 4, 7, 11, 14, 15, 18, Int.max] {
        #expect(index.position(atUTF8Offset: offset, columnEncoding: .utf8) == nil)
        #expect(index.position(atUTF8Offset: offset, columnEncoding: .utf16) == nil)
    }
    #expect(snapshot.text.utf8.elementsEqual("a😀e\u{301}\r\né\r中\n".utf8))
}

@Test(arguments: [
    ("", [1], [1]),
    ("abc", [1, 1, 1, 1], [1, 2, 3, 4]),
    ("\n", [1, 2], [1, 1]),
    ("\r", [1, 2], [1, 1]),
    ("\r\n", [1, 1, 2], [1, 2, 1]),
    ("a\r\nb", [1, 1, 1, 2, 2], [1, 2, 3, 1, 2]),
    ("\r\r\n", [1, 2, 2, 3], [1, 1, 2, 1]),
    ("\n\r", [1, 2, 3], [1, 1, 1]),
    ("\n\n", [1, 2, 3], [1, 1, 1]),
])
func sourcePositionsDefineNewlineAndEOFBoundaries(text: String, lines: [Int], columns: [Int]) throws {
    let index = SourcePositionIndex(snapshot: SourceSnapshot(text: text, language: .ruby))
    for offset in 0 ... text.utf8.count {
        for encoding: SourcePosition.ColumnEncoding in [.utf8, .utf16] {
            let position = try #require(index.position(atUTF8Offset: offset, columnEncoding: encoding))
            #expect(position.line == lines[offset])
            #expect(position.column == columns[offset])
        }
    }
    #expect(index.position(atUTF8Offset: -1, columnEncoding: .utf16) == nil)
    #expect(index.position(atUTF8Offset: text.utf8.count + 1, columnEncoding: .utf16) == nil)
}

@Test func sourcePositionsValidateRangeOwnershipAndBothEndpoints() throws {
    let snapshot = SourceSnapshot(text: "😀\r\nend", language: .swift)
    let index = SourcePositionIndex(snapshot: snapshot)
    let copy = snapshot
    let range = try #require(copy.range(0 ..< 6))
    let start = try #require(index.position(in: range, columnEncoding: .utf16))
    let end = try #require(index.position(in: range, at: .end, columnEncoding: .utf16))
    #expect(start.line == 1)
    #expect(start.column == 1)
    #expect(start.utf8Offset == 0)
    #expect(end.line == 2)
    #expect(end.column == 1)
    #expect(end.utf8Offset == 6)
    #expect(index.snapshotID == snapshot.id)

    let eof = try #require(snapshot.range(9 ..< 9))
    #expect(index.position(in: eof, columnEncoding: .utf16)
        == index.position(in: eof, at: .end, columnEncoding: .utf16))
    let other = SourceSnapshot(text: snapshot.text, language: .swift)
    let foreign = try #require(other.range(0 ..< 6))
    #expect(index.position(in: foreign, columnEncoding: .utf16) == nil)
    #expect(index.position(in: foreign, at: .end, columnEncoding: .utf8) == nil)
    let edited = SourcePositionIndex(snapshot: SourceSnapshot(text: " " + snapshot.text, language: .swift))
    #expect(edited.position(in: range, columnEncoding: .utf16) == nil)

    let copiedIndex = index
    #expect(copiedIndex.position(in: range, columnEncoding: .utf16) == start)
    #expect(SourcePositionIndex(snapshot: copy).position(in: range, at: .end, columnEncoding: .utf16) == end)
}

@Test func sourcePositionsDoNotNormalizeTextOrExpandTabs() throws {
    let snapshot = SourceSnapshot(text: "\té e\u{301}\u{2028}x", language: .swift)
    let index = SourcePositionIndex(snapshot: snapshot)
    // Tabs count as one code unit; Unicode line separator is an ordinary scalar.
    let position = try #require(index.position(atUTF8Offset: 11, columnEncoding: .utf16))
    #expect(position.line == 1)
    #expect(position.column == 8)
    #expect(index.position(atUTF8Offset: 2, columnEncoding: .utf16) == nil)
    #expect(index.position(atUTF8Offset: 6, columnEncoding: .utf16) == nil)
}

@Test func sourcePositionIndexCanBeSharedAcrossConcurrentLookups() async {
    let snapshot = SourceSnapshot(text: String(repeating: "😀é\r\n", count: 1000), language: .swift)
    let index = SourcePositionIndex(snapshot: snapshot)
    let positions = await withTaskGroup(of: SourcePosition?.self) { group in
        for line in 0 ..< 1000 {
            group.addTask {
                index.position(atUTF8Offset: line * 8 + 6, columnEncoding: .utf16)
            }
        }
        var results: [SourcePosition] = []
        for await result in group {
            if let result {
                results.append(result)
            }
        }
        return results.sorted { $0.line < $1.line }
    }
    #expect(positions.count == 1000)
    #expect(positions.map(\.line) == Array(1 ... 1000))
    #expect(positions.allSatisfy { $0.column == 4 && $0.snapshotID == snapshot.id })
}
