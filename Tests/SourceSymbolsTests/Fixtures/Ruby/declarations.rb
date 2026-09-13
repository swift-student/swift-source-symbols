# Documentation is not a declaration.
module Shop
  class Cart < Base
    VERSION = "1"
    def initialize(items = [])
      @items = items
    end
    def add(item, urgent: false, **options, &block)
      item
    end
    def self.build(...) = new(...)
    class << self
      def empty? = true
    end
    alias append add
  end
  class Cart
    def add(item) = item
  end
  module Helpers
    def ready?; true; end
  end
end
class Shop::Cart
  def [](index) = @items[index]
  def []=(index, value)
    @items[index] = value
  end
end
def top(value)
  def nested; end
end
def client.refresh!; end
