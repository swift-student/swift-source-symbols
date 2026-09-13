func labels(value local: Int, _ hidden: String, discarded _: Bool) {}
func defaults(value: Int /* before default */ = 1, done: () -> Void = { let value = 2; print(value) }) {}
func escaped(`repeat` `for`: Int) {}
func pack<each T>(_ values: repeat each T) {}
