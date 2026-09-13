func convert<T, U>(_ transform: @escaping (T, Int) throws -> U = { _, _ in fatalError() }, into values: inout [U]) async throws -> [U] where U: Equatable { [] }
func gather(values: Int...) {}
func choose(value: Int) -> String { "" }
func choose(value: Int) -> Int { value }
func identity<T>(value: T) -> T where T: Equatable { value }
func identity<T>(value: T) -> T where T: Hashable { value }
func typed(value: Int) throws(Failure) -> Int { value }
func call(_ work: () throws -> Void) rethrows { try work() }
func pair(value: (Int, String) = (1, "a,b"), done: () -> Void = {}) {}
func qualified(value: Swift.Int) {}
struct Number {
    static func + (lhs: Number, rhs: Number) -> Number { lhs }
    static func == (lhs: Number, rhs: Number) -> Bool { true }
    init?(value: Int) {}
    subscript(key index: Int) -> Int { index }
}
class Lifetime {
    deinit {}
}
