enum Event {
    case ready, payload(value: Int), raw(Int), mixed(Int, label: [String: (Int, String)], Bool)
    case `repeat`(`for`: Int = 1, callback: (Int, String) -> Void = { _, _ in })
    case café(😀: String), é(Int)
    case choice(value: Int), choice(text: String), choice(value: String)
}
enum Raw: Int {
    case one = 1, two = 2
}
