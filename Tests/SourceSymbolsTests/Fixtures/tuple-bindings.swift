let (x: a, y: b) = (x: 1, y: 2)
let (outer: (inner: `repeat`, ignored: _), tail: c) = (outer: (inner: 1, ignored: 2), tail: 3)

func bindings() {
    let (only, _) = { let temporary = 1; return (temporary, 2) }()
    let (_, (nested, _)) = { let nestedTemporary = 2; return (1, (nestedTemporary, 3)) }()
    let (label: labeled, ignored: _) = { let labeledTemporary = 3; return (label: labeledTemporary, ignored: 4) }()
    let (single) = { let singleTemporary = 4; return singleTemporary }()
    let (first, _) = (1, 2), second = { let secondTemporary = 5; return secondTemporary }()
}
