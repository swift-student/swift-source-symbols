import SourceSymbols

let snapshot = SourceSnapshot(text: """
struct Example {
    func run(value: Int) {}
    func run(value: String) {}
}
""", language: .swift)
let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
if case let .unique(declaration) = DeclarationMatcher.match(
    DeclarationQuery(name: .qualified("Example.run(value:)"), parameterTypes: ["Int"]),
    in: result.declarations
) {
    print(snapshot.text(in: declaration.declarationRange) ?? "")
}

for diagnostic in result.diagnostics {
    print(diagnostic.message)
}
