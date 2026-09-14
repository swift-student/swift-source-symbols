/// Leading documentation is not part of a header.
@available(*, deprecated, message: "use { replacement }")
public struct Store<T>: Sendable where T: Sendable {
    func refresh(force: Bool) {}
    func refresh(force: Int) {}

    @Header({ ["{": "}"] })
    public func transform<U>(
        _ value: U,
        using callback: @Sendable (U) -> String = { _ in "{}" }
    ) async throws(Failure) -> String
    where U: Equatable /* before body */ {
        callback(value)
    }

    var computed: Int { get { 1 } set {} }
    var observed = 0 { willSet {} didSet {} }
    let closure: () -> Int = { { 1 }() }
    let first = 1, second: String = "two"
    let (left, right) = (1, 2)
    init?(value: T) {}
    init!(other value: T) {}
    subscript(key index: Int) -> T { fatalError() }
    typealias Pair = (T, T)
}

extension Store where T: Equatable {}
protocol Headers {
    associatedtype Item: Equatable
    var required: Item { get set }
    func bodyless(value local: Item) async throws -> Item
    init(value: Item)
    subscript(index: Int) -> Item { get }
}
enum Event {
    indirect case payload(value: Int, callback: (Int) -> String), ready
}
enum Raw: Int { case one = 1, two = 2 }
class Lifetime { deinit {} }
func café(
    😀 é: String = "😀"
) -> String { é }
