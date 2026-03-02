module RailsInformant
  class BreadcrumbBuffer
    CAPACITY = 50

    def self.current
      RailsInformant::Current.breadcrumbs ||= new
    end

    def initialize
      @crumbs = []
    end

    def record(category:, message:, metadata: {}, duration: nil)
      @crumbs << {
        category:,
        message:,
        metadata:,
        duration:,
        timestamp: Time.current.iso8601(3)
      }
      @crumbs.shift if @crumbs.size > CAPACITY
    end

    def flush
      result = @crumbs
      @crumbs = []
      result
    end
  end
end
