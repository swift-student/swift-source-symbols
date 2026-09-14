import SourceSymbols
import Testing

/// Fixture expectations are authored from source bytes, independently of any backend.
struct ExpectedDeclaration: Decodable, Equatable {
    let name: String
    let kind: String
    let scopes: [String]
    let identifierRange: [Int]
    let declarationRange: [Int]

    init(_ declaration: Declaration) {
        name = declaration.name
        kind = declaration.kind.rawValue
        scopes = declaration.enclosingScopes
        identifierRange = [declaration.identifierRange.utf8Offsets.lowerBound,
                           declaration.identifierRange.utf8Offsets.upperBound]
        declarationRange = [declaration.declarationRange.utf8Offsets.lowerBound,
                            declaration.declarationRange.utf8Offsets.upperBound]
    }
}

func expectSnapshotContract(_ result: ExtractionResult, from snapshot: SourceSnapshot) throws {
    #expect(result.snapshot.id == snapshot.id)
    #expect(result.snapshot.language == snapshot.language)
    #expect(result.snapshot.text.utf8.elementsEqual(snapshot.text.utf8))
    let ranges = result.declarations.flatMap { [$0.identifierRange, $0.declarationRange] }
        + result.declarations.compactMap(\.headerRange)
        + result.diagnostics.compactMap(\.range)
    for range in ranges {
        #expect(range.snapshotID == snapshot.id)
        #expect(snapshot.range(range.utf8Offsets) == range)
        #expect(snapshot.text(in: range) != nil)
        let utf16 = try #require(snapshot.utf16Offsets(for: range))
        #expect(snapshot.range(utf16Offsets: utf16) == range)
    }
    for declaration in result.declarations {
        if let header = declaration.headerRange {
            #expect(header.utf8Offsets.lowerBound >= declaration.declarationRange.utf8Offsets.lowerBound)
            #expect(header.utf8Offsets.upperBound <= declaration.declarationRange.utf8Offsets.upperBound)
            #expect(header.utf8Offsets.lowerBound <= declaration.identifierRange.utf8Offsets.lowerBound)
            #expect(header.utf8Offsets.upperBound >= declaration.identifierRange.utf8Offsets.upperBound)
        }
        #expect(declaration.identifierRange.utf8Offsets.lowerBound >= declaration.declarationRange.utf8Offsets
            .lowerBound)
        #expect(declaration.identifierRange.utf8Offsets.upperBound <= declaration.declarationRange.utf8Offsets
            .upperBound)
    }
}

func expectBackendContract(_ result: ExtractionResult, from snapshot: SourceSnapshot,
                           declarations: [ExpectedDeclaration], diagnosticRanges: [Range<Int>?],
                           diagnosticSeverity: ParseDiagnostic.Severity = .error) throws
{
    try expectSnapshotContract(result, from: snapshot)
    // Array equality checks all declarations and diagnostics, including their order and duplicates.
    #expect(result.declarations.map(ExpectedDeclaration.init) == declarations)
    #expect(result.diagnostics.map { $0.range?.utf8Offsets } == diagnosticRanges)
    #expect(result.diagnostics.allSatisfy { $0.severity == diagnosticSeverity })
}

func expectMatches(_ query: DeclarationQuery, in result: ExtractionResult,
                   identifierOffsets: [Range<Int>])
{
    let declarations: [Declaration]
    switch DeclarationMatcher.match(query, in: result.declarations) {
    case .missing:
        #expect(identifierOffsets.isEmpty)
        declarations = []
    case let .unique(declaration):
        #expect(identifierOffsets.count == 1)
        declarations = [declaration]
    case let .ambiguous(candidates):
        #expect(identifierOffsets.count > 1)
        declarations = candidates
    }
    #expect(declarations.map(\.identifierRange.utf8Offsets) == identifierOffsets)
}
