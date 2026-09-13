/// A small in-memory navigation index used as representative application syntax.
struct NavigationIndex<Key: Hashable> {
    struct Entry {
        let key: Key
        let offsets: Range<Int>
    }

    private var entries: [Key: [Entry]] = [:]

    init(entries: [Entry] = []) {
        for entry in entries {
            self.entries[entry.key, default: []].append(entry)
        }
    }

    mutating func insert(_ entry: Entry) {
        entries[entry.key, default: []].append(entry)
    }

    func matches(for key: Key, accepting predicate: (Entry) -> Bool = { _ in true }) -> [Entry] {
        (entries[key] ?? []).filter(predicate)
    }

    func map<T>(_ transform: (Entry) throws -> T) rethrows -> [T] {
        try entries.values.flatMap { try $0.map(transform) }
    }

    var isEmpty: Bool { entries.isEmpty }
}

extension NavigationIndex.Entry {
    func contains(_ offset: Int) -> Bool {
        offsets.contains(offset)
    }
}
