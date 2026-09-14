import Foundation
import SourceSymbols
import Testing

@Test(arguments: ["source-link-navigation-lf", "source-link-navigation-crlf"])
func sourceLinkNavigationPositions(name: String) throws {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "swift", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let snapshot = try SourceSnapshot(text: #require(String(data: data, encoding: .utf8)), language: .swift)
    #expect(snapshot.text.utf8.contains(13) == name.hasSuffix("crlf"))
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    let index = SourcePositionIndex(snapshot: snapshot)
    // Source Link PR #14's lookup corpus, with independently specified identifier columns.
    let expected: [(DeclarationQuery.Name, [Int], [Int])] = [
        (.qualified("Widget.refresh(force:)"), [3, 4], [8, 8]),
        (.short("refresh"), [3, 4, 8, 10], [8, 8, 8, 21]),
        (.qualified("Widget.refresh()"), [8], [8]),
        (.qualified("Widget.Nested.go()"), [5], [24]),
        (.qualified("Widget.title"), [2], [7]),
        (.short("missing"), [], []),
        (.short("Café"), [11], [17]),
    ]
    for (name, lines, columns) in expected {
        let declarations: [Declaration] = switch DeclarationMatcher.match(
            .init(name: name),
            in: result.declarations
        ) {
        case .missing: []
        case let .unique(declaration): [declaration]
        case let .ambiguous(candidates): candidates
        }
        let positions = try declarations.map {
            try #require(index.position(in: $0.identifierRange, columnEncoding: .utf16))
        }
        #expect(positions.map(\.line) == lines)
        #expect(positions.map(\.column) == columns)
    }
    let cafe = try #require(result.declarations.first { $0.name == "Café" })
    #expect(snapshot.text(in: cafe.identifierRange) == "Café")
    let start = try #require(index.position(in: cafe.identifierRange, columnEncoding: .utf8))
    let end = try #require(index.position(in: cafe.identifierRange, at: .end, columnEncoding: .utf16))
    #expect(start.line == 11)
    #expect(start.column == 19)
    #expect(end.line == 11)
    #expect(end.column == 21)
    // The pinned grammar's block-comment false positive coexists with useful positions.
    #expect(!result.diagnostics.isEmpty)
    try expectSnapshotContract(result, from: snapshot)
}
