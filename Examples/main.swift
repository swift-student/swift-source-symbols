import SourceSymbols

/// A fixture adapter demonstrates the contract while production backends are evaluated.
struct ExampleExtractor: DeclarationExtractor {
    func extract(from snapshot: SourceSnapshot) throws -> ExtractionResult {
        guard snapshot.language == .swift else {
            throw ExtractionError.unsupportedLanguage(snapshot.language)
        }
        guard snapshot.text == "struct Example {}",
              let identifier = snapshot.range(7 ..< 14),
              let declaration = snapshot.range(0 ..< 17)
        else { return try ExtractionResult(snapshot: snapshot, declarations: []) }
        return try ExtractionResult(snapshot: snapshot, declarations: [
            Declaration(name: "Example", qualifiedName: "Example", kind: .type,
                        identifierRange: identifier, declarationRange: declaration),
        ])
    }
}

let snapshot = SourceSnapshot(text: "struct Example {}", language: .swift)
let result = try ExampleExtractor().extract(from: snapshot)
if case let .unique(declaration) = DeclarationMatcher.match(
    DeclarationQuery(name: .short("Example")), in: result.declarations
) {
    print(snapshot.text(in: declaration.identifierRange) ?? "")
}
