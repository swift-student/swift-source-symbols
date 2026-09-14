# Leading documentation is not part of a header.
module Shop
  class Cart < Factory.build({key: -> { 1 }})
    private def refresh(force = true); force; end
    def refresh(force = 1) = force
    def self.build(
      value = {key: -> { "{}" }},
      label: "😀",
      **options, &block
    )
      value
    end
    def bare value, label: "ok"; value; end
    def empty; end
    def forwarded(...) = target(...)
    def destructured((left, right)); left; end
    def reject(**nil); end
    alias :again :refresh
    class << self
      def singleton; end
    end
    FIRST, SECOND = 1, 2
  end
end

def default_doc(value = <<~TEXT)
  content
TEXT
end

def body_doc = <<~TEXT
  content
TEXT

def café(
  value = "😀"
)
  value
end
