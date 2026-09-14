class Host
  self::VALUE = 1
  class self::Nested
    def run; end
  end
  module self::Helpers
    def help; end
  end
  def (self::Nested).build; end
  class << self
    self::META = 2
    class self::Deep
      def run; end
    end
  end
end
holder::VALUE = 3
class holder::Nested
  def run; end
end
module holder::Tools
  def run; end
end
