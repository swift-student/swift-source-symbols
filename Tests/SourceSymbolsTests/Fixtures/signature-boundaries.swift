func implicitlyUnwrapped(_ value: Int!) -> String! { nil }
func callback() -> @Sendable () -> Void { {} }
func nested(value: ((Int, String) -> Bool)?) -> (Int, String) { (0, "") }
func constrained<T>(value: T) -> T! where T: AnyObject { nil }
func ownership(_ value: borrowing Int, other: consuming Int) {}
func spaced(value: /* leading */ [Int /* interior */]) -> /* leading */ String /* trailing */ { "" }
