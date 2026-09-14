struct Host {
    func outer(value: Int) {
        func inner() {}
        let local = value
        func middle(_ input: Int) {
            func leaf(flag: Bool) {}
        }
        struct Nested {
            func member() { let body = 1 }
        }
        let closure = { let captured = value; return captured }
    }
    func outer(text: String) { func inner() {} }
    func outer(value: String) { func inner() {} }
    init(seed: Int) { let local = seed }
    subscript(key index: Int) -> Int { let local = index; return local }
}
extension Host {
    func `repeat`(`for` input: Int) { func café(😀: Int) { let é = 1 } }
}
class Lifetime {
    deinit { let local = 1 }
}
func anonymous() {
    if true { let repeated = 1 }
    if false { let repeated = 2 }
}
