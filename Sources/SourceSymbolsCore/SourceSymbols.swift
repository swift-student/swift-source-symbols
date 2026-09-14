import Foundation

/// Languages recognized by the API; extraction availability depends on the backend.
public enum SourceLanguage: String, Hashable, Sendable {
    case swift, ruby
}

/// Immutable source text. Ranges are meaningful only within this snapshot.
public struct SourceSnapshot: Sendable {
    public let id: UUID
    public let text: String
    public let language: SourceLanguage

    public init(text: String, language: SourceLanguage) {
        id = UUID()
        self.text = text
        self.language = language
    }

    /// Validates zero-based, half-open UTF-8 byte offsets at Unicode scalar boundaries.
    public func range(_ offsets: Range<Int>) -> SourceRange? {
        guard offsets.lowerBound >= 0, offsets.upperBound <= text.utf8.count,
              scalarBoundary(offsets.lowerBound), scalarBoundary(offsets.upperBound)
        else { return nil }
        return SourceRange(snapshotID: id, utf8Offsets: offsets)
    }

    public func text(in range: SourceRange) -> String? {
        guard range.snapshotID == id else { return nil }
        return String(decoding: text.utf8.dropFirst(range.utf8Offsets.lowerBound)
            .prefix(range.utf8Offsets.count), as: UTF8.self)
    }

    /// Converts UTF-16 offsets without accepting boundaries inside a surrogate pair.
    public func range(utf16Offsets offsets: Range<Int>) -> SourceRange? {
        guard offsets.lowerBound >= 0, offsets.upperBound <= text.utf16.count else { return nil }
        let lower = text.utf16.index(text.utf16.startIndex, offsetBy: offsets.lowerBound)
        let upper = text.utf16.index(text.utf16.startIndex, offsetBy: offsets.upperBound)
        guard let lowerUTF8 = lower.samePosition(in: text.utf8),
              let upperUTF8 = upper.samePosition(in: text.utf8) else { return nil }
        return range(text.utf8.distance(from: text.utf8.startIndex, to: lowerUTF8)
            ..< text.utf8.distance(from: text.utf8.startIndex, to: upperUTF8))
    }

    public func utf16Offsets(for range: SourceRange) -> Range<Int>? {
        guard range.snapshotID == id else { return nil }
        let lower = text.utf8.index(text.utf8.startIndex, offsetBy: range.utf8Offsets.lowerBound)
        let upper = text.utf8.index(text.utf8.startIndex, offsetBy: range.utf8Offsets.upperBound)
        guard let lowerUTF16 = lower.samePosition(in: text.utf16),
              let upperUTF16 = upper.samePosition(in: text.utf16) else { return nil }
        return text.utf16.distance(from: text.utf16.startIndex, to: lowerUTF16)
            ..< text.utf16.distance(from: text.utf16.startIndex, to: upperUTF16)
    }

    private func scalarBoundary(_ offset: Int) -> Bool {
        let index = text.utf8.index(text.utf8.startIndex, offsetBy: offset)
        return index.samePosition(in: text.unicodeScalars) != nil
    }
}

public struct SourceRange: Hashable, Sendable {
    public let snapshotID: UUID
    public let utf8Offsets: Range<Int>
    fileprivate init(snapshotID: UUID, utf8Offsets: Range<Int>) {
        self.snapshotID = snapshotID
        self.utf8Offsets = utf8Offsets
    }
}

/// Syntactic callable information, not a type-checked identity. Strings retain interior trivia.
public struct CallableSignature: Equatable, Sendable {
    public struct Parameter: Equatable, Sendable {
        /// How arguments are supplied. `block` is a separate language-level channel,
        /// not every positional parameter whose type happens to be a closure.
        public enum Passing: String, Sendable {
            case positional, keyword, variadicPositional, variadicKeyword, block
        }

        /// The local binding name; nil when there is no single named binding.
        public let name: String?
        /// An external argument label or keyword; nil when the argument is unlabeled.
        public let argumentLabel: String?
        /// Nil when no type annotation is present. Never inferred from a value or default.
        public let typeSyntax: String?
        /// Positional parameters may still have labels, as in Swift.
        public let passing: Passing
        /// Records the presence of a default, without including its expression.
        public let hasDefaultValue: Bool

        public init(name: String? = nil, argumentLabel: String? = nil, typeSyntax: String? = nil,
                    passing: Passing = .positional, hasDefaultValue: Bool = false)
        {
            self.name = name
            self.argumentLabel = argumentLabel
            self.typeSyntax = typeSyntax
            self.passing = passing
            self.hasDefaultValue = hasDefaultValue
        }
    }

    public let parameters: [Parameter]
    public let genericParameters: String?
    public let effects: [String]
    public let returnType: String?
    public let genericConstraints: String?

    public init(parameters: [Parameter], genericParameters: String? = nil, effects: [String] = [],
                returnType: String? = nil, genericConstraints: String? = nil)
    {
        self.parameters = parameters
        self.genericParameters = genericParameters
        self.effects = effects
        self.returnType = returnType
        self.genericConstraints = genericConstraints
    }
}

public struct Declaration: Sendable {
    public enum Kind: String, Sendable {
        case type, function, method, property, variable, initializer, deinitializer, subscriptDeclaration
        case extensionScope, typeAlias, associatedType, enumCase, other
    }

    public let name: String
    /// Backend-defined lookup path; it need not be the lexical scope names joined together.
    public let qualifiedName: String
    public let kind: Kind
    /// Nil for non-callables or a callable whose header could not be recovered reliably.
    public let signature: CallableSignature?
    /// Optional exact lookup spellings supplied by the backend, never synthesized by the core.
    public let callableName: String?
    public let qualifiedCallableName: String?

    /// Outer-to-inner lexical scope names, including extension scopes. These are not lookup aliases.
    public let enclosingScopes: [String]
    public let identifierRange: SourceRange
    /// Exact source header, excluding implementation/accessor bodies under backend conventions.
    /// Nil when a reliable contiguous header is unavailable. Independent of matching metadata.
    public let headerRange: SourceRange?
    public let declarationRange: SourceRange

    public init(name: String, qualifiedName: String, kind: Kind, signature: CallableSignature? = nil,
                callableName: String? = nil, qualifiedCallableName: String? = nil,
                enclosingScopes: [String] = [], identifierRange: SourceRange,
                declarationRange: SourceRange, headerRange: SourceRange? = nil) throws
    {
        guard identifierRange.snapshotID == declarationRange.snapshotID,
              identifierRange.utf8Offsets.lowerBound >= declarationRange.utf8Offsets.lowerBound,
              identifierRange.utf8Offsets.upperBound <= declarationRange.utf8Offsets.upperBound
        else { throw ExtractionError.invalidRanges }
        if let headerRange {
            guard headerRange.snapshotID == declarationRange.snapshotID,
                  headerRange.utf8Offsets.lowerBound >= declarationRange.utf8Offsets.lowerBound,
                  headerRange.utf8Offsets.upperBound <= declarationRange.utf8Offsets.upperBound,
                  identifierRange.utf8Offsets.lowerBound >= headerRange.utf8Offsets.lowerBound,
                  identifierRange.utf8Offsets.upperBound <= headerRange.utf8Offsets.upperBound
            else { throw ExtractionError.invalidRanges }
        }
        self.name = name
        self.qualifiedName = qualifiedName
        self.kind = kind
        self.signature = signature
        self.callableName = callableName
        self.qualifiedCallableName = qualifiedCallableName
        self.enclosingScopes = enclosingScopes
        self.identifierRange = identifierRange
        self.headerRange = headerRange
        self.declarationRange = declarationRange
    }
}

public enum ExtractionError: Error, Sendable {
    case unsupportedLanguage(SourceLanguage)
    case invalidRanges
}

public struct ParseDiagnostic: Sendable {
    public enum Severity: Sendable { case warning, error }
    public let severity: Severity
    public let message: String
    public let range: SourceRange?
    public init(severity: Severity, message: String, range: SourceRange? = nil) {
        self.severity = severity
        self.message = message
        self.range = range
    }
}

public struct ExtractionResult: Sendable {
    public let snapshot: SourceSnapshot
    public let declarations: [Declaration]
    public let diagnostics: [ParseDiagnostic]

    public init(snapshot: SourceSnapshot, declarations: [Declaration],
                diagnostics: [ParseDiagnostic] = []) throws
    {
        guard declarations.allSatisfy({ $0.declarationRange.snapshotID == snapshot.id }),
              diagnostics.allSatisfy({ $0.range == nil || $0.range?.snapshotID == snapshot.id })
        else { throw ExtractionError.invalidRanges }
        self.snapshot = snapshot
        self.declarations = declarations
        self.diagnostics = diagnostics
    }
}

/// Backends report recovered declarations alongside diagnostics; unsupported languages throw.
public protocol DeclarationExtractor: Sendable {
    func extract(from snapshot: SourceSnapshot) throws -> ExtractionResult
}

public struct DeclarationQuery: Sendable {
    public enum Name: Sendable { case short(String), qualified(String) }
    public let name: Name
    /// An exact ordered annotation list. A nil element requires an absent annotation;
    /// a nil list omits the filter. An empty list requires a known zero-parameter signature.
    public let parameterTypes: [String?]?
    public let signature: CallableSignature?
    public init(name: Name, parameterTypes: [String?]? = nil, signature: CallableSignature? = nil) {
        self.name = name
        self.parameterTypes = parameterTypes
        self.signature = signature
    }
}

public enum DeclarationMatch: Sendable {
    case missing
    case unique(Declaration)
    case ambiguous([Declaration])
}

public enum DeclarationMatcher {
    /// Exact, case-sensitive matching in input order. Never arbitrarily selects an overload.
    public static func match(_ query: DeclarationQuery, in declarations: [Declaration]) -> DeclarationMatch {
        let candidates = declarations.filter { declaration in
            let nameMatches: Bool = switch query.name {
            case let .short(name): declaration.name == name || declaration.callableName == name
            case let .qualified(name): declaration.qualifiedName == name || declaration.qualifiedCallableName == name
            }
            guard nameMatches else { return false }
            let parameterTypes = declaration.signature?.parameters.map(\.typeSyntax)
            let typesMatch = query.parameterTypes == nil || query.parameterTypes == parameterTypes
            let signatureMatches = query.signature == nil || query.signature == declaration.signature
            return typesMatch && signatureMatches
        }
        switch candidates.count {
        case 0: return .missing
        case 1: return .unique(candidates[0])
        default: return .ambiguous(candidates)
        }
    }
}
