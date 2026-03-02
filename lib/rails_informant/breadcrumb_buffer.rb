module RailsInformant
  class BreadcrumbBuffer
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
      @crumbs.shift if @crumbs.size > capacity
    end

    def flush
      result = @crumbs.dup
      @crumbs.clear
      result
    end

    def size
      @crumbs.size
    end

    private

    def capacity
      RailsInformant.breadcrumb_capacity
    end
  end
end
