struct Store {
    var count: Int = 0
    let title = "Store", enabled = true
    func run() {}
    func run(value: Int) {}
    func run(value: String) {}
    func run(other value: Int) {}
    struct Nested {
        func run(value: Int) {}
    }
    init(count: Int) { self.count = count }
    subscript(index: Int) -> Int { index }
}
extension Store.Nested {
    func extra() {}
}
protocol Runnable {
    associatedtype Output
    var value: Output { get }
    func run(value: Output) -> Output
}
typealias Count = Int
enum State {
    case idle, ready(Int)
}
let (left, right) = (1, 2)
func outer() {
    let local = 1
    func inner() {}
}
