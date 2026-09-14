import Foundation

/// A scalar boundary in one immutable snapshot. Lines and columns are one-based.
public struct SourcePosition: Hashable, Sendable {
    public enum ColumnEncoding: Hashable, Sendable {
        case utf8, utf16
    }

    public let snapshotID: UUID
    public let utf8Offset: Int
    public let line: Int
    public let column: Int
    public let columnEncoding: ColumnEncoding

    fileprivate init(snapshotID: UUID, utf8Offset: Int, line: Int, column: Int,
                     columnEncoding: ColumnEncoding)
    {
        self.snapshotID = snapshotID
        self.utf8Offset = utf8Offset
        self.line = line
        self.column = column
        self.columnEncoding = columnEncoding
    }
}

/// Reusable source-position lookup for one snapshot, independent of any parser.
/// Build once and reuse for all declarations. Copies share immutable index storage.
public struct SourcePositionIndex: Sendable {
    public enum Endpoint: Sendable {
        case start, end
    }

    public let snapshotID: UUID
    private let utf8Count: Int
    private let lines: [LineStart]
    private let nonASCIIScalars: [ScalarSpan]

    private struct LineStart: Sendable {
        let utf8Offset: Int
        let utf16Offset: Int
    }

    private struct ScalarSpan: Sendable {
        let utf8Range: Range<Int>
        /// Cumulative difference between UTF-8 and UTF-16 offsets after this scalar.
        let extraUTF8Count: Int
    }

    /// Indexes LF, CRLF, and lone CR as line breaks without changing source bytes.
    public init(snapshot: SourceSnapshot) {
        snapshotID = snapshot.id
        var lines = [LineStart(utf8Offset: 0, utf16Offset: 0)]
        var nonASCIIScalars: [ScalarSpan] = []
        var utf8Offset = 0
        var utf16Offset = 0
        var previousWasCR = false

        for scalar in snapshot.text.unicodeScalars {
            let start = utf8Offset
            utf8Offset += scalar.utf8.count
            utf16Offset += scalar.utf16.count
            if utf8Offset - start > 1 {
                nonASCIIScalars.append(ScalarSpan(utf8Range: start ..< utf8Offset,
                                                  extraUTF8Count: utf8Offset - utf16Offset))
            }
            if scalar == "\n" || scalar == "\r" {
                let nextLine = LineStart(utf8Offset: utf8Offset, utf16Offset: utf16Offset)
                if scalar == "\n", previousWasCR {
                    // A CRLF line begins after LF, including when the pair ends at EOF.
                    lines[lines.count - 1] = nextLine
                } else {
                    lines.append(nextLine)
                }
            }
            previousWasCR = scalar == "\r"
        }

        utf8Count = utf8Offset
        self.lines = lines
        self.nonASCIIScalars = nonASCIIScalars
    }

    /// Converts a range's start or exclusive end. Foreign-snapshot ranges return nil.
    public func position(in range: SourceRange, at endpoint: Endpoint = .start,
                         columnEncoding: SourcePosition.ColumnEncoding) -> SourcePosition?
    {
        guard range.snapshotID == snapshotID else { return nil }
        let offset = switch endpoint {
        case .start: range.utf8Offsets.lowerBound
        case .end: range.utf8Offsets.upperBound
        }
        return position(atUTF8Offset: offset, columnEncoding: columnEncoding)
    }

    /// Interprets a zero-based byte offset in the indexed snapshot. Out-of-bounds
    /// offsets and offsets inside a scalar return nil. EOF is valid. At CRLF's
    /// interior boundary, the position remains on the preceding line, after CR.
    public func position(atUTF8Offset offset: Int,
                         columnEncoding: SourcePosition.ColumnEncoding) -> SourcePosition?
    {
        guard offset >= 0, offset <= utf8Count else { return nil }
        let scalarIndex = partitionIndex(nonASCIIScalars) { $0.utf8Range.upperBound <= offset }
        if scalarIndex < nonASCIIScalars.count,
           nonASCIIScalars[scalarIndex].utf8Range.lowerBound < offset
        {
            return nil
        }
        let lineIndex = partitionIndex(lines) { $0.utf8Offset <= offset } - 1
        let column: Int
        switch columnEncoding {
        case .utf8:
            column = offset - lines[lineIndex].utf8Offset + 1
        case .utf16:
            let extraUTF8Count = scalarIndex == 0 ? 0 : nonASCIIScalars[scalarIndex - 1].extraUTF8Count
            column = offset - extraUTF8Count - lines[lineIndex].utf16Offset + 1
        }
        return SourcePosition(snapshotID: snapshotID, utf8Offset: offset,
                              line: lineIndex + 1, column: column, columnEncoding: columnEncoding)
    }
}

/// First index after the sorted prefix satisfying the predicate; count if all do.
private func partitionIndex<Element>(_ values: [Element], while predicate: (Element) -> Bool) -> Int {
    var lower = 0
    var upper = values.count
    while lower < upper {
        let middle = lower + (upper - lower) / 2
        if predicate(values[middle]) {
            lower = middle + 1
        } else {
            upper = middle
        }
    }
    return lower
}
