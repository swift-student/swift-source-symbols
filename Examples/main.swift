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

let rubySnapshot = SourceSnapshot(text: """
class Client
  def deliver(value); value; end
  def deliver(value, timeout: 5); value; end
end
""", language: .ruby)
let rubyResult = try TreeSitterRubyExtractor().extract(from: rubySnapshot)
if case let .unique(declaration) = DeclarationMatcher.match(
    DeclarationQuery(name: .qualified("Client#deliver"), parameterTypes: [nil, nil]),
    in: rubyResult.declarations
) {
    print(rubySnapshot.text(in: declaration.declarationRange) ?? "")
}

for diagnostic in rubyResult.diagnostics {
    print(diagnostic.message)
}
