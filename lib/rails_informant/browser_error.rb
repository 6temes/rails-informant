module RailsInformant
  # Stands in for a JavaScript error so before_record callbacks can read
  # message and backtrace as they do for Ruby errors. The JS name lives in
  # the group's error_class string; no constant is ever made from it.
  class BrowserError < StandardError
    attr_reader :name

    def initialize(message, backtrace:, name:)
      super(message)
      @name = name
      set_backtrace backtrace
    end
  end
end
