=begin
class Commented
end
=end
text = "def fake; end"
pattern = /class Fake; end/
words = %q{module Fake; end}
message = <<~TEXT
  def fake_heredoc; end
TEXT
module Outer
  class Inner::Nested
    def self.run = 1
    def value=(value); @value = value; end
  end
  class ::Root
    def run; end
  end
  def Outer.helper; end
end
if condition
  class Choice; def run; end; end
else
  class Choice; def run; end; end
end
class << client
  def refresh!; end
  class << self
    def deep; end
  end
end
def (factory.call).build; end
private def hidden; end
__END__
class DataOnly
end
