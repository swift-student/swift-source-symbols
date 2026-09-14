DOC = <<~TEXT
  class Fake; end
TEXT
private def message = <<~TEXT
  #{def inside; end}
TEXT
PAIR = [<<~FIRST, <<~SECOND]
  one
FIRST
  two
SECOND
class Host
  def body
    <<~TEXT
      def fake; end
    TEXT
  end
end
OTHER = <<~TEXT; def later; end
  #{def owned_by_constant; end}
TEXT
def default_doc(value = <<~TEXT)
  content
TEXT
end
