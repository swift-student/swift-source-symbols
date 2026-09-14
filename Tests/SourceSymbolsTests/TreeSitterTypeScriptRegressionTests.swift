import Foundation
import SourceSymbols
import Testing

private func typeScriptRegressionFixture(_ name: String, language: SourceLanguage,
                                         newline: String = "\n") throws -> ExtractionResult
{
    let url = try #require(Bundle.module.url(
        forResource: name,
        withExtension: "ts",
        subdirectory: "Fixtures/TypeScript"
    ))
    let text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\n", with: newline)
    let snapshot = SourceSnapshot(text: text, language: language)
    let result = try TreeSitterTypeScriptExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    return result
}

@Test(arguments: [SourceLanguage.typescript, .tsx])
func typeScriptExportAssignmentsPreserveDeclarations(language: SourceLanguage) throws {
    let result = try typeScriptRegressionFixture("export-assignments", language: language)
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.qualifiedName) == [
        "Service", "Service.run", "factory", "factory.local", "Nested", "Nested.run",
    ])
    let service = try #require(result.declarations.first)
    #expect(service.headerRange.flatMap(result.snapshot.text) == "export = class Service")
    #expect(result.snapshot.text(in: service.declarationRange)
        == "export = class Service { run(value: string): void {} };")
    let factory = try #require(result.declarations.first { $0.name == "factory" })
    #expect(factory.headerRange.flatMap(result.snapshot.text) == "export = function factory(value: number)")
    #expect(factory.signature?.parameters == [.init(name: "value", typeSyntax: "number")])
    expectMatches(.init(name: .qualified("Service.run"), parameterTypes: ["string"]), in: result,
                  identifierOffsets: [result.declarations[1].identifierRange.utf8Offsets])
    expectMatches(.init(name: .short("renamed")), in: result, identifierOffsets: [])
}

@Test(arguments: [SourceLanguage.typescript, .tsx], ["\n", "\r\n"])
func typeScriptDecoratedMembersPreserveRangesAndRecovery(language: SourceLanguage, newline: String) throws {
    let result = try typeScriptRegressionFixture("decorated-members", language: language, newline: newline)
    #expect(result.declarations.map(\.qualifiedName) == [
        "Café", "Café.method", "Café.method.local", "Café.value", "Café.value", "Café.callback",
        "Café.decorated", "Café.inDecorator", "Café.damaged", "Café.plain",
    ])
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics[0].range.flatMap(result.snapshot.text) == "@")
    let method = try #require(result.declarations.first { $0.name == "method" })
    let header = "@first(\"😀\") /* between decorators */" + newline + "  @second" + newline
        + "  method(value: string): void"
    #expect(method.headerRange.flatMap(result.snapshot.text) == header)
    #expect(result.snapshot.text(in: method.declarationRange) == header + " { const local = value; }")
    #expect(method.signature?.parameters == [.init(name: "value", typeSyntax: "string")])
    let accessors = result.declarations.filter { $0.name == "value" }
    #expect(accessors.map { $0.headerRange.flatMap(result.snapshot.text) } == [
        "@access get value(): string", "@access set value(input: string)",
    ])
    #expect(accessors.map { result.snapshot.text(in: $0.declarationRange) } == [
        "@access get value(): string { return \"\"; }", "@access set value(input: string) {}",
    ])
    expectMatches(.init(name: .qualified("Café.value")), in: result,
                  identifierOffsets: accessors.map(\.identifierRange.utf8Offsets))
    let field = try #require(result.declarations.first { $0.name == "callback" })
    #expect(field.headerRange.flatMap(result.snapshot.text) == "@field public callback = (value: string): void => {}")
    #expect(field.signature?.parameters == [.init(name: "value", typeSyntax: "string")])
    let damaged = try #require(result.declarations.first { $0.name == "damaged" })
    #expect(damaged.headerRange == nil && damaged.signature == nil)
    #expect(result.snapshot.text(in: damaged.declarationRange) == "@broken(@) damaged(value: string): void {}")
    expectMatches(.init(name: .short("damaged"), parameterTypes: ["string"]), in: result, identifierOffsets: [])
    let plain = try #require(result.declarations.first { $0.name == "plain" })
    #expect(plain.headerRange.flatMap(result.snapshot.text) == "plain(): void")
}

@Test(arguments: [SourceLanguage.typescript, .tsx])
func typeScriptBindingDamageInvalidatesSignaturesButBodyErrorsDoNot(language: SourceLanguage) throws {
    let result = try typeScriptRegressionFixture("binding-recovery", language: language)
    #expect(!result.diagnostics.isEmpty)
    for name in ["broken", "Fields.broken", "missingCloser", "groupedCallable"] {
        let declaration = try #require(result.declarations.first { $0.qualifiedName == name })
        #expect(declaration.headerRange == nil && declaration.signature == nil)
        expectMatches(
            .init(name: .qualified(name)),
            in: result,
            identifierOffsets: [declaration.identifierRange.utf8Offsets]
        )
        expectMatches(.init(name: .qualified(name), parameterTypes: ["string"]), in: result, identifierOffsets: [])
    }
    for name in ["bodyError", "Fields.bodyError", "groupedBody", "groupedHealthy"] {
        let declaration = try #require(result.declarations.first { $0.qualifiedName == name })
        let type = name == "groupedHealthy" ? "number" : "string"
        // The full initializer is an unreliable header, but its callable prefix is sound.
        #expect(declaration.headerRange == nil)
        #expect(declaration.signature == .init(
            parameters: [.init(name: "value", typeSyntax: type)],
            returnType: "void"
        ))
        expectMatches(.init(name: .qualified(name), parameterTypes: [type]), in: result,
                      identifierOffsets: [declaration.identifierRange.utf8Offsets])
    }
}

@Test(arguments: [SourceLanguage.typescript, .tsx])
func typeScriptEnumInitializersPreserveDeclarationAndMatchOrder(language: SourceLanguage) throws {
    let result = try typeScriptRegressionFixture("enum-order", language: language)
    #expect(result.diagnostics.isEmpty)
    #expect(result.declarations.map(\.qualifiedName) == [
        "E", "E.A", "E.A.B", "E.B", "E.C", "E.C.nested", "E.C.nested.local", "E.D",
    ])
    expectMatches(.init(name: .short("B")), in: result, identifierOffsets: [
        result.declarations[2].identifierRange.utf8Offsets, result.declarations[3].identifierRange.utf8Offsets,
    ])
    let member = result.declarations[1]
    #expect(result.snapshot.text(in: member.declarationRange) == "A = (() => { const B = 1; return B; })()")
}
