module Config
  VERSION = "1"
  A, (B, Namespace::C) = 1, [2, 3]
  ::ROOT ||= 4
  local = A
  @instance = B
  @@shared = 0
  object.VALUE = C
  VALUES[0] = 1
  alias fresh old
  alias :ready? :old?
  alias $new $old
  alias_method :dynamic, :fresh
  attr_reader :generated
end
