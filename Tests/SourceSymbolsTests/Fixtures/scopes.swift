struct Host {
    var computed: Int { let local = 1; return local }
    let a: () -> Void = { func first() {} }, b: () -> Void = { func second() {} }
    var pair = { () -> (Int, Int) in let (x, y) = (1, 2); return (x, y) }()
    struct Inner {}
}
extension `Host` . `Inner` { func f() {} }
