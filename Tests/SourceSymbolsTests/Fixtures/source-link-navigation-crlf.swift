struct Widget {
  var title: String
  func refresh(force: Bool) {}
  func refresh(force: Int) {}
  struct Nested { func go() {} }
}
extension Widget {
  func refresh() {}
}
struct Other { func refresh() {} }
/* 🐱 */ struct Café {}
// func missing() {}