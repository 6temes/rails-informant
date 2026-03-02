module RailsInformant
  class StructuredEventSubscriber
    def emit(event)
      return unless RailsInformant.initialized?

      BreadcrumbBuffer.current.record(
        category: event[:name],
        message: event[:name],
        metadata: event[:payload].is_a?(Hash) ? event[:payload] : {},
        duration: nil
      )
    end
  end
end
